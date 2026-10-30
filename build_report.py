#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
derbytrade — формирование Excel-отчёта по базе торговли рыбными товарами ФАО.

Программа (см. задание в README.md):
  1. создаёт базу Apache Derby embedded ./derbydb из .xlsx дампов каталога ./XLSX
     (DDL берётся из trade_ddl.sql);
  2. выполняет SQL-запросы ИСКЛЮЧИТЕЛЬНО в диалекте Apache Derby
     (через JDBC-драйвер Derby, вызываемый из Python при помощи jpype);
  3. формирует report.xlsx, где каждый лист = таблица из задания:

     Таблица_1  Основные страны-экспортёры (стоимость, тыс. долл.)
     Таблица_2  Основные страны-экспортёры (вес, тонн)
     Таблица_3  Основные страны-импортёры (стоимость, тыс. долл.)
     Таблица_4  Основные страны-импортёры (вес, тонн)
     Таблица_5  Товарная структура мировой торговли по 10 группам FAO
     Таблица_6  Товарная структура мировой торговли по странам и группам

Запуск:
    pip install jpype1 pandas openpyxl
    # jars Apache Derby — в ./lib (derby.jar derbyshared.jar derbytools.jar)
    python build_report.py [--years 2021 2022 2023 2024] [--top 30] [--rebuild]

Все выполненные запросы логируются в queries_run.sql (диалект Derby).

Особенности диалекта Derby, учтённые в коде:
  * LIMIT/OFFSET отсутствует -> "FETCH FIRST n ROWS ONLY";
  * ORDER BY в подзапросе разрешён только вместе с FETCH FIRST;
  * нет FILTER/PIVOT/GROUPING SETS -> условные суммы SUM(CASE...) разворачиваются
    по годам на этапе генерации SQL (имена столбцов VALUE_Yxxxx нельзя
    параметризовать);
  * NULL в агрегатах -> COALESCE(x,0), т.к. SUM() по одним NULL даёт NULL;
  * оконные функции (ROW_NUMBER OVER) поддерживаются, но для TOP-N используется
    детерминированный ORDER BY ... DESC, код_страны ASC + FETCH FIRST.
"""

import argparse
import datetime as dt
import glob
import os
import shutil
import sys

import pandas as pd

# ---------------------------------------------------------------------------
# Конфигурация
# ---------------------------------------------------------------------------
HERE        = os.path.dirname(os.path.abspath(__file__))
XLSX_DIR    = os.path.join(HERE, "XLSX")
DB_DIR      = os.path.join(HERE, "derbydb")
LIB_DIR     = os.path.join(HERE, "lib")
OUT_XLSX    = os.path.join(HERE, "report.xlsx")
QUERIES_LOG = os.path.join(HERE, "queries_run.sql")

SCHEMA        = "FISHSTAT"
YEARS_DEFAULT = [2021, 2022, 2023, 2024]   # последние 4 года данных в базе
TOP_DEFAULT   = 30

VALUE_TABLES = {
    "V": ("TSD_TRADE_VALUE",    "V_USD_1000"),   # стоимость, тыс. долл.
    "Q": ("TSD_TRADE_QUANTITY", "Q_tpw"),        # вес, тонн
}


def vcol(year: int) -> str:
    """Имя столбца данных за год."""
    return f"VALUE_Y{year}"


# ---------------------------------------------------------------------------
# Слой доступа к Derby (JDBC через JPype)
# ---------------------------------------------------------------------------
class Derby:
    def __init__(self, create=True):
        import jpype
        jars = sorted(glob.glob(os.path.join(LIB_DIR, "*.jar")))
        if not jars:
            sys.exit("В каталоге lib/ нет .jar файлов Apache Derby.")
        if not jpype.isJVMStarted():
            jpype.startJVM(jpype.getDefaultJVMPath(),
                           "-Djava.class.path=" + os.path.pathsep.join(jars),
                           ignoreUnrecognized=True, convertStrings=True)
        import jpype.imports  # noqa: F401  (нужен для синтаксиса "from java... import")
        from java.sql import DriverManager
        self._dm = DriverManager
        # явная регистрация embedded-драйвера (после shutdown=true он deregister'ится)
        try:
            DriverManager.registerDriver(
                jpype.JClass("org.apache.derby.jdbc.EmbeddedDriver")())
        except Exception:
            pass
        url = f"jdbc:derby:{DB_DIR};create={'true' if create else 'false'}"
        self.conn = DriverManager.getConnection(url, SCHEMA, SCHEMA)
        self.conn.setAutoCommit(True)
        self._log = open(QUERIES_LOG, "a", encoding="utf-8")

    # ---- выполнение SQL -------------------------------------------------
    def _log_sql(self, sql):
        self._log.write(sql.strip() + "\n;\n\n")
        self._log.flush()

    def query(self, sql):
        """SELECT -> (список колонок, список строк)."""
        self._log_sql(sql)
        st = self.conn.createStatement()
        rs = st.executeQuery(sql)
        meta = rs.getMetaData()
        cols = [str(meta.getColumnLabel(i + 1)).upper()
                for i in range(meta.getColumnCount())]
        rows = []
        while rs.next():
            rows.append(tuple(rs.getObject(i + 1) for i in range(meta.getColumnCount())))
        rs.close(); st.close()
        return cols, rows

    def ddl(self, sql):
        self._log_sql(sql)
        st = self.conn.createStatement()
        st.execute(sql)
        st.close()

    def close(self):
        try:
            self.conn.commit()
        except Exception:
            pass
        self.conn.close()
        self._log.close()
        # обязательная остановка embedded-движка Derby
        try:
            self._dm.getConnection("jdbc:derby:;shutdown=true")
        except Exception:
            pass  # Derby всегда бросает 01Y00 «Derby system shutdown»


# ---------------------------------------------------------------------------
# Создание БД из дампов XLSX
# ---------------------------------------------------------------------------
TABLES_ORDER = ["REF_COMMODITY", "REF_COMMODITY_MAJOR2", "REF_COUNTRY_REPORTER",
                "REF_MEASURE", "REF_TRADE_FLOW", "REL_COMMODITY_MAJOR",
                "TSD_TRADE_QUANTITY", "TSD_TRADE_VALUE"]


def read_ddl_statements():
    """DDL-операторы из trade_ddl.sql (комментарии вырезаны)."""
    import re
    path = os.path.join(HERE, "trade_ddl.sql")
    text = open(path, encoding="utf-8").read()
    text = re.sub(r"--[^\n]*", "", text)              # строчные комментарии
    stmts = [s.strip() for s in text.split(";") if s.strip()]
    return stmts


def load_database(db: Derby):
    print(f"[1/4] Создание схемы {SCHEMA} и таблиц в {DB_DIR} ...")
    try:
        db.ddl(f"CREATE SCHEMA {SCHEMA}")
    except Exception:
        pass  # схема уже существует
    for st in read_ddl_statements():
        try:
            db.ddl(st)
        except Exception as e:
            msg = str(e)
            if "already exists" in msg or "X0Y9" in msg or "42S01" in msg \
               or "X0B3E" in msg or "42S15" in msg:
                continue
            raise

    print("[2/4] Загрузка данных из XLSX-дампов ...")
    for t in TABLES_ORDER:
        df = pd.read_excel(os.path.join(XLSX_DIR, t + ".xlsx"))
        df.columns = [c.upper() for c in df.columns]
        insert_table(db, t, df)
        print(f"      {t}: {len(df)} строк")


def insert_table(db: Derby, table: str, df: pd.DataFrame):
    cols = list(df.columns)
    sql = (f"INSERT INTO {SCHEMA}.{table} ({', '.join(cols)}) "
           f"VALUES ({', '.join(['?'] * len(cols))})")
    ps = db.conn.prepareStatement(sql)
    n = 0
    for row in df.itertuples(index=False, name=None):
        for i, v in enumerate(row, start=1):
            set_param(ps, i, v)
        ps.addBatch()
        n += 1
        if n % 5000 == 0:
            ps.executeBatch()
    ps.executeBatch()
    ps.close()


def set_param(ps, idx, v):
    if v is None or (isinstance(v, float) and pd.isna(v)) or pd.isna(v):
        ps.setNull(idx, 7)          # java.sql.Types.DOUBLE — нейтральный тип NULL
    elif isinstance(v, float):
        ps.setDouble(idx, v)
    elif isinstance(v, int):
        ps.setLong(idx, v)
    else:
        ps.setString(idx, str(v))


# ---------------------------------------------------------------------------
# Генераторы SQL-запросов (диалект Derby)
# ---------------------------------------------------------------------------
def q_country_all(table_measure, flow, years):
    """Агрегат по всем странам (GROUP BY страна) — источник строк и расчётов."""
    t, measure = table_measure
    sel = ",\n       ".join(f"SUM(COALESCE(t.{vcol(y)}, 0)) AS Y{y}" for y in years)
    return (f"SELECT COALESCE(t.COUNTRY_REPORTER, '???')            AS COUNTRY_CODE,\n"
            f"       MAX(COALESCE(c.NAME_EN, 'Неизвестная страна')) AS COUNTRY_NAME,\n"
            f"       {sel}\n"
            f"  FROM {SCHEMA}.{t} t\n"
            f"  LEFT JOIN {SCHEMA}.REF_COUNTRY_REPORTER c\n"
            f"         ON c.UN_CODE = t.COUNTRY_REPORTER\n"
            f" WHERE t.TRADE_FLOW = '{flow}'\n"
            f"   AND t.MEASURE    = '{measure}'\n"
            f" GROUP BY t.COUNTRY_REPORTER")


def q_top_subquery(table_measure, flow, years, top):
    """Подзапрос TOP-N стран по последнему году (используется в IN (...) и как основа листа)."""
    t, measure = table_measure
    last = vcol(years[-1])
    sel = ",\n       ".join(f"SUM(COALESCE(t.{vcol(y)}, 0)) AS Y{y}" for y in years)
    return (f"SELECT COALESCE(t.COUNTRY_REPORTER, '???')            AS COUNTRY_CODE,\n"
            f"       MAX(COALESCE(c.NAME_EN, 'Неизвестная страна')) AS COUNTRY_NAME,\n"
            f"       {sel}\n"
            f"  FROM {SCHEMA}.{t} t\n"
            f"  LEFT JOIN {SCHEMA}.REF_COUNTRY_REPORTER c\n"
            f"         ON c.UN_CODE = t.COUNTRY_REPORTER\n"
            f" WHERE t.TRADE_FLOW = '{flow}'\n"
            f"   AND t.MEASURE    = '{measure}'\n"
            f" GROUP BY t.COUNTRY_REPORTER\n"
            f" ORDER BY SUM(COALESCE(t.{last}, 0)) DESC, COUNTRY_CODE ASC\n"
            f" FETCH FIRST {top} ROWS ONLY")


def q_world_total(table_measure, flow, years):
    """МИР всего (одна строка сумм по годам)."""
    t, measure = table_measure
    sel = ",\n       ".join(f"SUM(COALESCE({vcol(y)}, 0)) AS Y{y}" for y in years)
    return (f"SELECT COUNT(*) AS ROWS_CNT,\n       {sel}\n"
            f"  FROM {SCHEMA}.{t}\n"
            f" WHERE TRADE_FLOW = '{flow}'\n"
            f"   AND MEASURE    = '{measure}'")


def q_top_sum(table_measure, flow, years, top):
    """СУММА TOP-N стран по годам (одна строка)."""
    t, measure = table_measure
    sel = ", ".join(f"SUM(COALESCE(t.{vcol(y)}, 0)) AS Y{y}" for y in years)
    inner = (f"SELECT t2.COUNTRY_REPORTER\n"
             f"          FROM {SCHEMA}.{t} t2\n"
             f"         WHERE t2.TRADE_FLOW = '{flow}'\n"
             f"           AND t2.MEASURE    = '{measure}'\n"
             f"         GROUP BY t2.COUNTRY_REPORTER\n"
             f"         ORDER BY SUM(COALESCE(t2.{vcol(years[-1])}, 0)) DESC,\n"
             f"                  t2.COUNTRY_REPORTER ASC\n"
             f"         FETCH FIRST {top} ROWS ONLY")
    return (f"SELECT 'TOP{top}' AS LIST_NAME, {sel}\n"
            f"  FROM {SCHEMA}.{t} t\n"
            f" WHERE t.TRADE_FLOW = '{flow}'\n"
            f"   AND t.MEASURE    = '{measure}'\n"
            f"   AND t.COUNTRY_REPORTER IN (\n        {inner})")


CM_JOIN = (f"  JOIN {SCHEMA}.REF_COMMODITY cm\n"
           f"         ON cm.FAO_CODE = {{a}}.COMMODITY\n"
           f"  JOIN {SCHEMA}.REL_COMMODITY_MAJOR r\n"
           f"         ON r.CHILD_ID = cm.ID\n"
           f"  JOIN {SCHEMA}.REF_COMMODITY_MAJOR2 m2\n"
           f"         ON m2.ID = r.PARENT_ID\n")


def _group_part(kind, flow, years, with_country=False):
    """Одна часть UNION ALL: группировка по 10 группам FAO (или группа×страна).

    with_country=True — Таблица 6: БЕЗ ограничений по странам, все страны,
    присутствующие в факте (правило TOP-N относится только к таблицам 1–4).
    """
    t, measure = VALUE_TABLES[kind]
    dtype = "C" if kind == "V" else "K"
    a = "t"
    sel = ",\n       ".join(f"SUM(COALESCE({a}.{vcol(y)}, 0)) AS Y{y}" for y in years)
    cc = (f"{a}.COUNTRY_REPORTER AS COUNTRY_CODE,\n"
          f"       MAX(c.NAME_EN) AS COUNTRY_NAME,\n       "
          if with_country else "")
    gb = f"{a}.COUNTRY_REPORTER, " if with_country else ""
    cj = (f"  LEFT JOIN {SCHEMA}.REF_COUNTRY_REPORTER c\n"
          f"         ON c.UN_CODE = {a}.COUNTRY_REPORTER\n"
          if with_country else "")
    return (f"SELECT {cc}m2.CODE AS GROUP_CODE,\n"
            f"       MAX(m2.NAME_EN) AS GROUP_NAME,\n"
            f"       '{dtype}' AS DATA_TYPE,\n"
            f"       {sel}\n"
            f"  FROM {SCHEMA}.{t} {a}\n" + cj + CM_JOIN.format(a=a) +
            f" WHERE {a}.TRADE_FLOW = '{flow}'\n"
            f"   AND {a}.MEASURE    = '{measure}'\n"
            f" GROUP BY {gb}m2.CODE")


def q_groups(flow, years, with_country=False):
    """Товарная структура по 10 группам: UNION стоимости (C) и веса (K)."""
    parts = [_group_part("V", flow, years, with_country),
             _group_part("Q", flow, years, with_country)]
    order = "1, 3, 5" if with_country else "1, 3"
    return "\nUNION ALL\n".join(parts) + f"\nORDER BY {order}"


def q_groups_total(flow, years):
    """ВСЕГО ПО 10 ГРУППАМ (итого) — сумма по всей таблице (100% покрытия проверено)."""
    parts = []
    for kind, label in (("V", "C"), ("Q", "K")):
        t, measure = VALUE_TABLES[kind]
        sel = ", ".join(f"SUM(COALESCE({vcol(y)}, 0)) AS Y{y}" for y in years)
        parts.append(f"SELECT 'TOTAL' AS GROUP_CODE,\n"
                     f"       'ВСЕГО ПО 10 ГРУППАМ' AS GROUP_NAME,\n"
                     f"       '{label}' AS DATA_TYPE, {sel}\n"
                     f"  FROM {SCHEMA}.{t}\n"
                     f" WHERE TRADE_FLOW = '{flow}'\n"
                     f"   AND MEASURE    = '{measure}'")
    return "\nUNION ALL\n".join(parts)


# ---------------------------------------------------------------------------
# Сборка листов (результаты запросов -> строки Excel)
# ---------------------------------------------------------------------------
def fnum(v):
    return float(v) if v is not None else 0.0


def sheet_countries(db, years, top, kind, flow, unit_label, basis_kind):
    """Листы 1–4. Топ-30 стран по уровню последнего года + итоги.

    Список топ-30 всегда берётся по стоимости (basis_kind='V'), как задано
    вTables 1–4 («по убыванию уровню последнего года» таблицы-первоисточника
    rankings построены по тому же показателю, что и таблица).
    """
    tm = VALUE_TABLES[kind]
    _, all_rows = db.query(q_country_all(tm, flow, years))
    by_code = {r[0]: r for r in all_rows}
    _, top_rows = db.query(q_top_subquery(tm, flow, years, top))
    _, world_row = db.query(q_world_total(tm, flow, years))
    _, topsum_row = db.query(q_top_sum(tm, flow, years, top))

    world = [fnum(x) for x in world_row[0][1:]]
    topsum = [fnum(x) for x in topsum_row[0][1:]]
    rest = [w - t for w, t in zip(world, topsum)]

    header = ["Страна"] + [f"{y} ({unit_label})" for y in years]
    rows = []
    # названия стран — as is из базы (NAME_EN), без нумерации и прочих правок
    for r in top_rows:
        rows.append([r[1]] + [fnum(x) for x in r[2:]])
    rows.append(["СУММА (ВСЕГО ЗА ГОД)"] + world)
    rows.append([f"СУММА {top} СТРАН-ЛИДЕРОВ"] + topsum)
    rows.append(["ПРОЧИЕ СТРАНЫ (ВСЕГО МИНУС ЛИДЕРЫ)"] + rest)
    return header, rows


GROUP_LABELS_CACHE = {}


def group_list(db):
    if not GROUP_LABELS_CACHE:
        _, g = db.query(f"SELECT CODE, NAME_EN FROM {SCHEMA}.REF_COMMODITY_MAJOR2"
                        f" ORDER BY CODE")
        GROUP_LABELS_CACHE.update({code: name for code, name in g})
    return [(c, n) for c, n in
            sorted(GROUP_LABELS_CACHE.items(), key=lambda kv: kv[0])]


def sheet_group_structure(db, years):
    """Лист 5: 10 групп × (К/С) × экспорт/импорт × годы."""
    groups = group_list(db)
    header = (["Товарная группа FAO", "Тип (К/С)"] +
              [f"Экспорт {y}" for y in years] + [f"Импорт {y}" for y in years])

    exp = {(r[0], r[2]): r for r in db.query(q_groups("E", years))[1]}
    imp = {(r[0], r[2]): r for r in db.query(q_groups("I", years))[1]}
    tot_e = {(r[0], r[2]): r for r in db.query(q_groups_total("E", years))[1]}
    tot_i = {(r[0], r[2]): r for r in db.query(q_groups_total("I", years))[1]}

    rows = []
    for dt_key in ("K", "C"):
        e = tot_e.get(("TOTAL", dt_key)); i = tot_i.get(("TOTAL", dt_key))
        ev = [fnum(x) for x in e[3:]] if e else [0.0] * len(years)
        iv = [fnum(x) for x in i[3:]] if i else [0.0] * len(years)
        rows.append(["ВСЕГО ПО 10 ГРУППАМ", "К" if dt_key == "K" else "С"]
                    + ev + iv)
    for gcode, gname in groups:
        for dt_key in ("K", "C"):
            e = exp.get((gcode, dt_key)); i = imp.get((gcode, dt_key))
            ev = [fnum(x) for x in e[3:]] if e else [0.0] * len(years)
            iv = [fnum(x) for x in i[3:]] if i else [0.0] * len(years)
            # название группы — as is из базы (NAME_EN), без нумерации
            rows.append([gname, "К" if dt_key == "K" else "С"] + ev + iv)
    return header, rows


def sheet_country_structure(db, years):
    """Лист 6: товарная структура по ВСЕМ странам (без TOP-ограничений).
    Две первые колонки: «Страна» и «Товарная группа FAO».
    """
    groups = group_list(db)
    header = (["Страна", "Товарная группа FAO", "Тип (К/С)"] +
              [f"Экспорт {y}" for y in years] + [f"Импорт {y}" for y in years])

    ge = {(r[0], r[2]): r for r in db.query(q_groups("E", years))[1]}
    gi = {(r[0], r[2]): r for r in db.query(q_groups("I", years))[1]}
    te = {(r[0], r[2]): r for r in db.query(q_groups_total("E", years))[1]}
    ti = {(r[0], r[2]): r for r in db.query(q_groups_total("I", years))[1]}

    _, ref_c = db.query(f"SELECT UN_CODE, NAME_EN FROM {SCHEMA}.REF_COUNTRY_REPORTER")
    ref_names = dict(ref_c)

    ec = db.query(q_groups("E", years, with_country=True))[1]
    ic = db.query(q_groups("I", years, with_country=True))[1]
    emap = {(r[0], r[2], r[4]): r for r in ec}
    imap = {(r[0], r[2], r[4]): r for r in ic}
    codes = sorted({r[0] for r in ec} | {r[0] for r in ic})
    names = {}
    for r in ec + ic:
        if r[0] not in names or names[r[0]] is None:
            names[r[0]] = r[1]
    for code in codes:
        if names.get(code) is None:
            names[code] = ref_names.get(code, code)

    def gsum(m1, m2, code, dt_key):
        ev = [0.0] * len(years)
        iv = [0.0] * len(years)
        for gcode, _ in groups:
            e = m1.get((code, gcode, dt_key))
            i = m2.get((code, gcode, dt_key))
            if e:
                ev = [ev[k] + fnum(e[5 + k]) for k in range(len(years))]
            if i:
                iv = [iv[k] + fnum(i[5 + k]) for k in range(len(years))]
        return ev, iv

    rows = []
    # Всего по 10 группам (итого по миру)
    for dt_key in ("K", "C"):
        e = te.get(("TOTAL", dt_key)); i = ti.get(("TOTAL", dt_key))
        ev = [fnum(x) for x in e[3:]] if e else [0.0] * len(years)
        iv = [fnum(x) for x in i[3:]] if i else [0.0] * len(years)
        rows.append(["ВСЕГО ПО 10 ГРУППАМ", "", "К" if dt_key == "K" else "С"] + ev + iv)

    # Итоги по каждой из 10 групп
    for gcode, gname in groups:
        for dt_key in ("K", "C"):
            e = ge.get((gcode, dt_key)); i = gi.get((gcode, dt_key))
            ev = [fnum(x) for x in e[3:]] if e else [0.0] * len(years)
            iv = [fnum(x) for x in i[3:]] if i else [0.0] * len(years)
            rows.append(["", gname, "К" if dt_key == "K" else "С"] + ev + iv)

    ordered_codes = sorted(codes, key=lambda c: (names[c], c))
    for code in ordered_codes:
        name = names[code]
        # Итог по стране
        for dt_key in ("K", "C"):
            ev, iv = gsum(emap, imap, code, dt_key)
            rows.append([name, "", "К" if dt_key == "K" else "С"] + ev + iv)
        # Детализация: страна × группа
        for gcode, gname in groups:
            for dt_key in ("K", "C"):
                e = emap.get((code, gcode, dt_key))
                i = imap.get((code, gcode, dt_key))
                ev = [fnum(x) for x in e[5:]] if e else [0.0] * len(years)
                iv = [fnum(x) for x in i[5:]] if i else [0.0] * len(years)
                rows.append([name, gname,
                             "К" if dt_key == "K" else "С"] + ev + iv)
    return header, rows


# ---------------------------------------------------------------------------
# Запись Excel
# ---------------------------------------------------------------------------
def write_excel(sheets):
    from openpyxl import Workbook
    from openpyxl.styles import Font, Alignment, PatternFill
    wb = Workbook()
    wb.remove(wb.active)
    bold = Font(bold=True)
    fill = PatternFill("solid", fgColor="DDEBF7")
    for title, (header, rows) in sheets.items():
        ws = wb.create_sheet(title[:31])
        ws.append(header)
        for c in ws[1]:
            c.font = bold
            c.fill = fill
            c.alignment = Alignment(horizontal="center", wrap_text=True)
        for r in rows:
            ws.append(list(r))
        maxw = max([len(str(header[0]))] + [len(str(r[0])) for r in rows] or [10])
        ws.column_dimensions["A"].width = min(64, max(14, maxw + 2))
        for col in "BCDEFGHIJKLMNOPQRSTUVWXYZ":
            ws.column_dimensions[col].width = 15
        for row in ws.iter_rows(min_row=2):
            first = row[0].value
            strong = isinstance(first, str) and (
                first.startswith(("СУММА", "ВСЕГО", "ПРОЧИЕ", "ИТОГО")))
            for c in row:
                if isinstance(c.value, float):
                    c.number_format = "#,##0"
                if strong:
                    c.font = bold
        ws.freeze_panes = "B2"
    wb.save(OUT_XLSX)
    print(f"[4/4] Отчёт сохранён: {OUT_XLSX}")


# ---------------------------------------------------------------------------
# main
# ---------------------------------------------------------------------------
def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[1])
    ap.add_argument("--years", nargs="+", type=int, default=YEARS_DEFAULT,
                    help="4 последних года отчёта (по умолчанию 2021-2024)")
    ap.add_argument("--top", type=int, default=TOP_DEFAULT,
                    help="число стран-лидеров для таблиц 1–4 (по умолчанию 30; "
                         "Таблица 6 формируется по всем странам без ограничений)")
    ap.add_argument("--rebuild", action="store_true",
                    help="пересоздать базу Derby из XLSX-дампов")
    args = ap.parse_args()
    years, top = args.years, args.top
    assert len(years) == 4, "нужно ровно 4 года"

    fresh = not os.path.exists(DB_DIR)
    if args.rebuild and os.path.exists(DB_DIR):
        shutil.rmtree(DB_DIR)
        fresh = True

    if fresh:
        open(QUERIES_LOG, "w", encoding="utf-8").write(
            "-- Выполненные SQL-запросы (диалект Apache Derby)\n"
            f"-- Сформировано: {dt.datetime.now().isoformat(timespec='seconds')}\n\n")
        db = Derby(create=True)
        try:
            load_database(db)
        finally:
            db.close()

    db = Derby(create=False)
    try:
        print("[3/4] Выполнение SQL-запросов Derby и сборка листов ...")
        sheets = {}
        specs = [("Таблица_1", "V", "E", "тыс. долл."),
                 ("Таблица_2", "Q", "E", "тонн"),
                 ("Таблица_3", "V", "I", "тыс. долл."),
                 ("Таблица_4", "Q", "I", "тонн")]
        for name, kind, flow, unit in specs:
            h, rows = sheet_countries(db, years, top, kind, flow, unit, None)
            sheets[name] = (h, rows)
        sheets["Таблица_5"] = sheet_group_structure(db, years)
        # Таблица 6 — ВСЕ страны, без TOP-ограничений
        sheets["Таблица_6"] = sheet_country_structure(db, years)
        write_excel(sheets)
    finally:
        db.close()


if __name__ == "__main__":
    main()
