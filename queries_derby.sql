-- ============================================================================
-- derbytrade: SQL-запросы в диалекте Apache Derby (10.14+)
-- База: FISHSTAT (торговля рыбными товарами ФАО, "страна-мир")
--
-- Соглашения (см. README.md / trade_ddl.sql):
--   * используются только поля _EN; SYMBOL_*, EBXID и прочие не описанные поля игнорируются;
--   * TRADE_FLOW: 'E' = экспорт, 'I' = импорт, 'R' = реэкспорт — ИГНОРИРУЕТСЯ во всех запросах;
--   * MEASURE: 'V_USD_1000' (стоимость, тыс. долл.) и 'Q_tpw' (вес, тонн);
--   * последние 4 года данных в базе: 2021, 2022, 2023, 2024;
--   * NULL в полях VALUE_Yxxxx трактуются как 0 (COALESCE), что для Derby важно,
--     т.к. агрегатная функция SUM() возвращает NULL если все значения NULL;
--   * топ-30 стран определяются по уровню ПОСЛЕДНЕГО года (2024) с детерминированным
--     разрешением ничьих (по коду страны).
--
-- Ограничения диалекта Derby, учтённые в запросах:
--   * нет FILTER (WHERE ...), нет параметризации имён столбцов -> годы разворачиваются
--     оператором Python-программы (build_report.py) в явные выражения SUM(CASE...);
--   * ORDER BY в подзапросе допустим только вместе с FETCH FIRST (LIMIT заменяется на
--     "FETCH FIRST n ROWS ONLY");
--   * нет FULL OUTER JOIN -> объединение таблиц по ключу эмулируется LEFT JOIN + UNION
--     + RIGHT JOIN через подзапросы;
--   * нет PIVOT / UNPIVOT / GROUPING SETS / CUBE -> разворот по годам делается через
--     SUM(CASE WHEN ... THEN ... ELSE 0 END), итоговые строки — отдельными SELECT + UNION ALL;
--   * табличные функции (FROM ... FOR ...) в 10.14 нет -> список лет задаётся конструкцией
--     (VALUES ...) как производная таблица (поддержано) или константами в коде;
--   * агрегаты нельзя использовать в WHERE -> фильтры перенесены в HAVING/подзапросы;
--   * имена столбцев результата приводятся к UPPER CASE (как и все идентификаторы Derby).
-- ============================================================================


-- ############################################################################
-- ЗАПРОСЫ ДЛЯ ТАБЛИЦ 1–4: основные страны-экспортёры / импортёры
--   (по стоимости, тыс. долл. — TSD_TRADE_VALUE; по весу, тонн — TSD_TRADE_QUANTITY)
-- ############################################################################

-- ---------------------------------------------------------------------------
-- Q1. Сводка по всем странам-экспортёрам за последние 4 года (стоимость).
--     Используется для расчёта "ВСЕГО" и "ПРОЧИЕ СТРАНЫ".
--     Источник строк таблицы 1.
-- ---------------------------------------------------------------------------
SELECT COALESCE(t.COUNTRY_REPORTER, '???')                    AS COUNTRY_CODE,
       MAX(COALESCE(c.NAME_EN, 'Неизвестная страна'))         AS COUNTRY_NAME,
       SUM(COALESCE(t.VALUE_Y2021, 0))                        AS Y2021,
       SUM(COALESCE(t.VALUE_Y2022, 0))                        AS Y2022,
       SUM(COALESCE(t.VALUE_Y2023, 0))                        AS Y2023,
       SUM(COALESCE(t.VALUE_Y2024, 0))                        AS Y2024
  FROM FISHSTAT.TSD_TRADE_VALUE t
  LEFT JOIN FISHSTAT.REF_COUNTRY_REPORTER c
         ON c.UN_CODE = t.COUNTRY_REPORTER
 WHERE t.TRADE_FLOW = 'E'
   AND t.MEASURE    = 'V_USD_1000'
 GROUP BY t.COUNTRY_REPORTER;


-- ---------------------------------------------------------------------------
-- Q2. ТОП-30 стран-экспортёров по стоимости (сортировка по последнему году).
--     Строки 2..31 таблицы 1.
-- ---------------------------------------------------------------------------
SELECT COALESCE(t.COUNTRY_REPORTER, '???')                    AS COUNTRY_CODE,
       MAX(COALESCE(c.NAME_EN, 'Неизвестная страна'))         AS COUNTRY_NAME,
       SUM(COALESCE(t.VALUE_Y2021, 0))                        AS Y2021,
       SUM(COALESCE(t.VALUE_Y2022, 0))                        AS Y2022,
       SUM(COALESCE(t.VALUE_Y2023, 0))                        AS Y2023,
       SUM(COALESCE(t.VALUE_Y2024, 0))                        AS Y2024
  FROM FISHSTAT.TSD_TRADE_VALUE t
  LEFT JOIN FISHSTAT.REF_COUNTRY_REPORTER c
         ON c.UN_CODE = t.COUNTRY_REPORTER
 WHERE t.TRADE_FLOW = 'E'
   AND t.MEASURE    = 'V_USD_1000'
 GROUP BY t.COUNTRY_REPORTER
 ORDER BY SUM(COALESCE(t.VALUE_Y2024, 0)) DESC, COUNTRY_CODE ASC
 FETCH FIRST 30 ROWS ONLY;


-- ---------------------------------------------------------------------------
-- Q3. МИР (всего) по экспорту, стоимость: одна строка с суммами по каждому году.
--     Строка "ВСЕГО" таблицы 1.
-- ---------------------------------------------------------------------------
SELECT COUNT(*)                                    AS ROWS_CNT,
       SUM(COALESCE(VALUE_Y2021, 0))               AS Y2021,
       SUM(COALESCE(VALUE_Y2022, 0))               AS Y2022,
       SUM(COALESCE(VALUE_Y2023, 0))               AS Y2023,
       SUM(COALESCE(VALUE_Y2024, 0))               AS Y2024
  FROM FISHSTAT.TSD_TRADE_VALUE
 WHERE TRADE_FLOW = 'E'
   AND MEASURE    = 'V_USD_1000';


-- ---------------------------------------------------------------------------
-- Q4. Сводка по всем странам-экспортёрам за последние 4 года (вес, тонн).
--     Источник строк таблицы 2.
-- ---------------------------------------------------------------------------
SELECT COALESCE(t.COUNTRY_REPORTER, '???')                    AS COUNTRY_CODE,
       MAX(COALESCE(c.NAME_EN, 'Неизвестная страна'))         AS COUNTRY_NAME,
       SUM(COALESCE(t.VALUE_Y2021, 0))                        AS Y2021,
       SUM(COALESCE(t.VALUE_Y2022, 0))                        AS Y2022,
       SUM(COALESCE(t.VALUE_Y2023, 0))                        AS Y2023,
       SUM(COALESCE(t.VALUE_Y2024, 0))                        AS Y2024
  FROM FISHSTAT.TSD_TRADE_QUANTITY t
  LEFT JOIN FISHSTAT.REF_COUNTRY_REPORTER c
         ON c.UN_CODE = t.COUNTRY_REPORTER
 WHERE t.TRADE_FLOW = 'E'
   AND t.MEASURE    = 'Q_tpw'
 GROUP BY t.COUNTRY_REPORTER;


-- ---------------------------------------------------------------------------
-- Q5. ТОП-30 стран-экспортёров по весу (сортировка по последнему году).
-- ---------------------------------------------------------------------------
SELECT COALESCE(t.COUNTRY_REPORTER, '???')                    AS COUNTRY_CODE,
       MAX(COALESCE(c.NAME_EN, 'Неизвестная страна'))         AS COUNTRY_NAME,
       SUM(COALESCE(t.VALUE_Y2021, 0))                        AS Y2021,
       SUM(COALESCE(t.VALUE_Y2022, 0))                        AS Y2022,
       SUM(COALESCE(t.VALUE_Y2023, 0))                        AS Y2023,
       SUM(COALESCE(t.VALUE_Y2024, 0))                        AS Y2024
  FROM FISHSTAT.TSD_TRADE_QUANTITY t
  LEFT JOIN FISHSTAT.REF_COUNTRY_REPORTER c
         ON c.UN_CODE = t.COUNTRY_REPORTER
 WHERE t.TRADE_FLOW = 'E'
   AND t.MEASURE    = 'Q_tpw'
 GROUP BY t.COUNTRY_REPORTER
 ORDER BY SUM(COALESCE(t.VALUE_Y2024, 0)) DESC, COUNTRY_CODE ASC
 FETCH FIRST 30 ROWS ONLY;


-- ---------------------------------------------------------------------------
-- Q6. МИР (всего) по экспорту, вес.
-- ---------------------------------------------------------------------------
SELECT COUNT(*)                                    AS ROWS_CNT,
       SUM(COALESCE(VALUE_Y2021, 0))               AS Y2021,
       SUM(COALESCE(VALUE_Y2022, 0))               AS Y2022,
       SUM(COALESCE(VALUE_Y2023, 0))               AS Y2023,
       SUM(COALESCE(VALUE_Y2024, 0))               AS Y2024
  FROM FISHSTAT.TSD_TRADE_QUANTITY
 WHERE TRADE_FLOW = 'E'
   AND MEASURE    = 'Q_tpw';


-- ---------------------------------------------------------------------------
-- Q7. Сводка по всем странам-импортёрам за последние 4 года (стоимость).
--     Источник строк таблицы 3.
-- ---------------------------------------------------------------------------
SELECT COALESCE(t.COUNTRY_REPORTER, '???')                    AS COUNTRY_CODE,
       MAX(COALESCE(c.NAME_EN, 'Неизвестная страна'))         AS COUNTRY_NAME,
       SUM(COALESCE(t.VALUE_Y2021, 0))                        AS Y2021,
       SUM(COALESCE(t.VALUE_Y2022, 0))                        AS Y2022,
       SUM(COALESCE(t.VALUE_Y2023, 0))                        AS Y2023,
       SUM(COALESCE(t.VALUE_Y2024, 0))                        AS Y2024
  FROM FISHSTAT.TSD_TRADE_VALUE t
  LEFT JOIN FISHSTAT.REF_COUNTRY_REPORTER c
         ON c.UN_CODE = t.COUNTRY_REPORTER
 WHERE t.TRADE_FLOW = 'I'
   AND t.MEASURE    = 'V_USD_1000'
 GROUP BY t.COUNTRY_REPORTER;


-- ---------------------------------------------------------------------------
-- Q8. ТОП-30 стран-импортёров по стоимости (сортировка по последнему году).
-- ---------------------------------------------------------------------------
SELECT COALESCE(t.COUNTRY_REPORTER, '???')                    AS COUNTRY_CODE,
       MAX(COALESCE(c.NAME_EN, 'Неизвестная страна'))         AS COUNTRY_NAME,
       SUM(COALESCE(t.VALUE_Y2021, 0))                        AS Y2021,
       SUM(COALESCE(t.VALUE_Y2022, 0))                        AS Y2022,
       SUM(COALESCE(t.VALUE_Y2023, 0))                        AS Y2023,
       SUM(COALESCE(t.VALUE_Y2024, 0))                        AS Y2024
  FROM FISHSTAT.TSD_TRADE_VALUE t
  LEFT JOIN FISHSTAT.REF_COUNTRY_REPORTER c
         ON c.UN_CODE = t.COUNTRY_REPORTER
 WHERE t.TRADE_FLOW = 'I'
   AND t.MEASURE    = 'V_USD_1000'
 GROUP BY t.COUNTRY_REPORTER
 ORDER BY SUM(COALESCE(t.VALUE_Y2024, 0)) DESC, COUNTRY_CODE ASC
 FETCH FIRST 30 ROWS ONLY;


-- ---------------------------------------------------------------------------
-- Q9. МИР (всего) по импорту, стоимость.
-- ---------------------------------------------------------------------------
SELECT COUNT(*)                                    AS ROWS_CNT,
       SUM(COALESCE(VALUE_Y2021, 0))               AS Y2021,
       SUM(COALESCE(VALUE_Y2022, 0))               AS Y2022,
       SUM(COALESCE(VALUE_Y2023, 0))               AS Y2023,
       SUM(COALESCE(VALUE_Y2024, 0))               AS Y2024
  FROM FISHSTAT.TSD_TRADE_VALUE
 WHERE TRADE_FLOW = 'I'
   AND MEASURE    = 'V_USD_1000';


-- ---------------------------------------------------------------------------
-- Q10. Сводка по всем странам-импортёрам за последние 4 года (вес, тонн).
--      Источник строк таблицы 4.
-- ---------------------------------------------------------------------------
SELECT COALESCE(t.COUNTRY_REPORTER, '???')                    AS COUNTRY_CODE,
       MAX(COALESCE(c.NAME_EN, 'Неизвестная страна'))         AS COUNTRY_NAME,
       SUM(COALESCE(t.VALUE_Y2021, 0))                        AS Y2021,
       SUM(COALESCE(t.VALUE_Y2022, 0))                        AS Y2022,
       SUM(COALESCE(t.VALUE_Y2023, 0))                        AS Y2023,
       SUM(COALESCE(t.VALUE_Y2024, 0))                        AS Y2024
  FROM FISHSTAT.TSD_TRADE_QUANTITY t
  LEFT JOIN FISHSTAT.REF_COUNTRY_REPORTER c
         ON c.UN_CODE = t.COUNTRY_REPORTER
 WHERE t.TRADE_FLOW = 'I'
   AND t.MEASURE    = 'Q_tpw'
 GROUP BY t.COUNTRY_REPORTER;


-- ---------------------------------------------------------------------------
-- Q11. ТОП-30 стран-импортёров по весу (сортировка по последнему году).
-- ---------------------------------------------------------------------------
SELECT COALESCE(t.COUNTRY_REPORTER, '???')                    AS COUNTRY_CODE,
       MAX(COALESCE(c.NAME_EN, 'Неизвестная страна'))         AS COUNTRY_NAME,
       SUM(COALESCE(t.VALUE_Y2021, 0))                        AS Y2021,
       SUM(COALESCE(t.VALUE_Y2022, 0))                        AS Y2022,
       SUM(COALESCE(t.VALUE_Y2023, 0))                        AS Y2023,
       SUM(COALESCE(t.VALUE_Y2024, 0))                        AS Y2024
  FROM FISHSTAT.TSD_TRADE_QUANTITY t
  LEFT JOIN FISHSTAT.REF_COUNTRY_REPORTER c
         ON c.UN_CODE = t.COUNTRY_REPORTER
 WHERE t.TRADE_FLOW = 'I'
   AND t.MEASURE    = 'Q_tpw'
 GROUP BY t.COUNTRY_REPORTER
 ORDER BY SUM(COALESCE(t.VALUE_Y2024, 0)) DESC, COUNTRY_CODE ASC
 FETCH FIRST 30 ROWS ONLY;


-- ---------------------------------------------------------------------------
-- Q12. МИР (всего) по импорту, вес.
-- ---------------------------------------------------------------------------
SELECT COUNT(*)                                    AS ROWS_CNT,
       SUM(COALESCE(VALUE_Y2021, 0))               AS Y2021,
       SUM(COALESCE(VALUE_Y2022, 0))               AS Y2022,
       SUM(COALESCE(VALUE_Y2023, 0))               AS Y2023,
       SUM(COALESCE(VALUE_Y2024, 0))               AS Y2024
  FROM FISHSTAT.TSD_TRADE_QUANTITY
 WHERE TRADE_FLOW = 'I'
   AND MEASURE    = 'Q_tpw';


-- ---------------------------------------------------------------------------
-- Q13. Контрольный запрос: сумма по ТОП-30 экспортёрам (стоимость) по годам.
--      Строка "СУММА 30 СТРАН" таблицы 1. Аналогичные запросы генерируются
--      программой для остальных трёх таблиц (Q14, Q15, Q16).
--      Внутренний запрос повторяет Q2 (TOP-30), поэтому список стран
--      гарантированно совпадает со строками таблицы.
-- ---------------------------------------------------------------------------
SELECT 'ТОП-30 ЭКСПОРТ СТОИМОСТЬ'                          AS LIST_NAME,
       SUM(COALESCE(t.VALUE_Y2021, 0))                     AS Y2021,
       SUM(COALESCE(t.VALUE_Y2022, 0))                     AS Y2022,
       SUM(COALESCE(t.VALUE_Y2023, 0))                     AS Y2023,
       SUM(COALESCE(t.VALUE_Y2024, 0))                     AS Y2024
  FROM FISHSTAT.TSD_TRADE_VALUE t
 WHERE t.TRADE_FLOW = 'E'
   AND t.MEASURE    = 'V_USD_1000'
   AND t.COUNTRY_REPORTER IN (
        SELECT t2.COUNTRY_REPORTER
          FROM FISHSTAT.TSD_TRADE_VALUE t2
         WHERE t2.TRADE_FLOW = 'E'
           AND t2.MEASURE    = 'V_USD_1000'
         GROUP BY t2.COUNTRY_REPORTER
         ORDER BY SUM(COALESCE(t2.VALUE_Y2024, 0)) DESC, t2.COUNTRY_REPORTER ASC
         FETCH FIRST 30 ROWS ONLY);


-- ---------------------------------------------------------------------------
-- Q14. Сумма по ТОП-30 экспортёрам (вес).
-- ---------------------------------------------------------------------------
SELECT 'ТОП-30 ЭКСПОРТ ВЕС'                                AS LIST_NAME,
       SUM(COALESCE(t.VALUE_Y2021, 0))                     AS Y2021,
       SUM(COALESCE(t.VALUE_Y2022, 0))                     AS Y2022,
       SUM(COALESCE(t.VALUE_Y2023, 0))                     AS Y2023,
       SUM(COALESCE(t.VALUE_Y2024, 0))                     AS Y2024
  FROM FISHSTAT.TSD_TRADE_QUANTITY t
 WHERE t.TRADE_FLOW = 'E'
   AND t.MEASURE    = 'Q_tpw'
   AND t.COUNTRY_REPORTER IN (
        SELECT t2.COUNTRY_REPORTER
          FROM FISHSTAT.TSD_TRADE_QUANTITY t2
         WHERE t2.TRADE_FLOW = 'E'
           AND t2.MEASURE    = 'Q_tpw'
         GROUP BY t2.COUNTRY_REPORTER
         ORDER BY SUM(COALESCE(t2.VALUE_Y2024, 0)) DESC, t2.COUNTRY_REPORTER ASC
         FETCH FIRST 30 ROWS ONLY);


-- ---------------------------------------------------------------------------
-- Q15. Сумма по ТОП-30 импортёрам (стоимость).
-- ---------------------------------------------------------------------------
SELECT 'ТОП-30 ИМПОРТ СТОИМОСТЬ'                           AS LIST_NAME,
       SUM(COALESCE(t.VALUE_Y2021, 0))                     AS Y2021,
       SUM(COALESCE(t.VALUE_Y2022, 0))                     AS Y2022,
       SUM(COALESCE(t.VALUE_Y2023, 0))                     AS Y2023,
       SUM(COALESCE(t.VALUE_Y2024, 0))                     AS Y2024
  FROM FISHSTAT.TSD_TRADE_VALUE t
 WHERE t.TRADE_FLOW = 'I'
   AND t.MEASURE    = 'V_USD_1000'
   AND t.COUNTRY_REPORTER IN (
        SELECT t2.COUNTRY_REPORTER
          FROM FISHSTAT.TSD_TRADE_VALUE t2
         WHERE t2.TRADE_FLOW = 'I'
           AND t2.MEASURE    = 'V_USD_1000'
         GROUP BY t2.COUNTRY_REPORTER
         ORDER BY SUM(COALESCE(t2.VALUE_Y2024, 0)) DESC, t2.COUNTRY_REPORTER ASC
         FETCH FIRST 30 ROWS ONLY);


-- ---------------------------------------------------------------------------
-- Q16. Сумма по ТОП-30 импортёрам (вес).
-- ---------------------------------------------------------------------------
SELECT 'ТОП-30 ИМПОРТ ВЕС'                                 AS LIST_NAME,
       SUM(COALESCE(t.VALUE_Y2021, 0))                     AS Y2021,
       SUM(COALESCE(t.VALUE_Y2022, 0))                     AS Y2022,
       SUM(COALESCE(t.VALUE_Y2023, 0))                     AS Y2023,
       SUM(COALESCE(t.VALUE_Y2024, 0))                     AS Y2024
  FROM FISHSTAT.TSD_TRADE_QUANTITY t
 WHERE t.TRADE_FLOW = 'I'
   AND t.MEASURE    = 'Q_tpw'
   AND t.COUNTRY_REPORTER IN (
        SELECT t2.COUNTRY_REPORTER
          FROM FISHSTAT.TSD_TRADE_QUANTITY t2
         WHERE t2.TRADE_FLOW = 'I'
           AND t2.MEASURE    = 'Q_tpw'
         GROUP BY t2.COUNTRY_REPORTER
         ORDER BY SUM(COALESCE(t2.VALUE_Y2024, 0)) DESC, t2.COUNTRY_REPORTER ASC
         FETCH FIRST 30 ROWS ONLY);


-- ############################################################################
-- ЗАПРОСЫ ДЛЯ ТАБЛИЦ 5–6: товарная структура мировой торговли (FAO major group)
--
-- Цепочка связей: TSD_*.COMMODITY = REF_COMMODITY.FAO_CODE,
--                 REL_COMMODITY_MAJOR.CHILD_ID = REF_COMMODITY.ID,
--                 REL_COMMODITY_MAJOR.PARENT_ID = REF_COMMODITY_MAJOR2.ID,
--                 REF_COMMODITY_MAJOR2.CODE — код группы ('1'..'9','A').
-- ############################################################################

-- ---------------------------------------------------------------------------
-- Q17. Товарная структура по 10 группам FAO: ЭКСПОРТ (стоимость и вес) по годам.
--      Каждая группа даёт две строки: тип 'C' (стоимость, тыс.долл.) и
--      тип 'K' (количество/вес, тонн). Сортировка — по коду группы.
-- ---------------------------------------------------------------------------
SELECT m2.CODE                                              AS GROUP_CODE,
       MAX(m2.NAME_EN)                                      AS GROUP_NAME,
       'C'                                                  AS DATA_TYPE,
       SUM(COALESCE(v.VALUE_Y2021, 0))                      AS Y2021,
       SUM(COALESCE(v.VALUE_Y2022, 0))                      AS Y2022,
       SUM(COALESCE(v.VALUE_Y2023, 0))                      AS Y2023,
       SUM(COALESCE(v.VALUE_Y2024, 0))                      AS Y2024
  FROM FISHSTAT.TSD_TRADE_VALUE v
  JOIN FISHSTAT.REF_COMMODITY    cm ON cm.FAO_CODE = v.COMMODITY
  JOIN FISHSTAT.REL_COMMODITY_MAJOR r ON r.CHILD_ID = cm.ID
  JOIN FISHSTAT.REF_COMMODITY_MAJOR2 m2 ON m2.ID = r.PARENT_ID
 WHERE v.TRADE_FLOW = 'E'
   AND v.MEASURE    = 'V_USD_1000'
 GROUP BY m2.CODE
UNION ALL
SELECT m2.CODE                                              AS GROUP_CODE,
       MAX(m2.NAME_EN)                                      AS GROUP_NAME,
       'K'                                                  AS DATA_TYPE,
       SUM(COALESCE(q.VALUE_Y2021, 0))                      AS Y2021,
       SUM(COALESCE(q.VALUE_Y2022, 0))                      AS Y2022,
       SUM(COALESCE(q.VALUE_Y2023, 0))                      AS Y2023,
       SUM(COALESCE(q.VALUE_Y2024, 0))                      AS Y2024
  FROM FISHSTAT.TSD_TRADE_QUANTITY q
  JOIN FISHSTAT.REF_COMMODITY    cm ON cm.FAO_CODE = q.COMMODITY
  JOIN FISHSTAT.REL_COMMODITY_MAJOR r ON r.CHILD_ID = cm.ID
  JOIN FISHSTAT.REF_COMMODITY_MAJOR2 m2 ON m2.ID = r.PARENT_ID
 WHERE q.TRADE_FLOW = 'E'
   AND q.MEASURE    = 'Q_tpw'
 GROUP BY m2.CODE
ORDER BY 1, 3;


-- ---------------------------------------------------------------------------
-- Q18. Товарная структура по 10 группам FAO: ИМПОРТ (стоимость и вес) по годам.
-- ---------------------------------------------------------------------------
SELECT m2.CODE                                              AS GROUP_CODE,
       MAX(m2.NAME_EN)                                      AS GROUP_NAME,
       'C'                                                  AS DATA_TYPE,
       SUM(COALESCE(v.VALUE_Y2021, 0))                      AS Y2021,
       SUM(COALESCE(v.VALUE_Y2022, 0))                      AS Y2022,
       SUM(COALESCE(v.VALUE_Y2023, 0))                      AS Y2023,
       SUM(COALESCE(v.VALUE_Y2024, 0))                      AS Y2024
  FROM FISHSTAT.TSD_TRADE_VALUE v
  JOIN FISHSTAT.REF_COMMODITY    cm ON cm.FAO_CODE = v.COMMODITY
  JOIN FISHSTAT.REL_COMMODITY_MAJOR r ON r.CHILD_ID = cm.ID
  JOIN FISHSTAT.REF_COMMODITY_MAJOR2 m2 ON m2.ID = r.PARENT_ID
 WHERE v.TRADE_FLOW = 'I'
   AND v.MEASURE    = 'V_USD_1000'
 GROUP BY m2.CODE
UNION ALL
SELECT m2.CODE                                              AS GROUP_CODE,
       MAX(m2.NAME_EN)                                      AS GROUP_NAME,
       'K'                                                  AS DATA_TYPE,
       SUM(COALESCE(q.VALUE_Y2021, 0))                      AS Y2021,
       SUM(COALESCE(q.VALUE_Y2022, 0))                      AS Y2022,
       SUM(COALESCE(q.VALUE_Y2023, 0))                      AS Y2023,
       SUM(COALESCE(q.VALUE_Y2024, 0))                      AS Y2024
  FROM FISHSTAT.TSD_TRADE_QUANTITY q
  JOIN FISHSTAT.REF_COMMODITY    cm ON cm.FAO_CODE = q.COMMODITY
  JOIN FISHSTAT.REL_COMMODITY_MAJOR r ON r.CHILD_ID = cm.ID
  JOIN FISHSTAT.REF_COMMODITY_MAJOR2 m2 ON m2.ID = r.PARENT_ID
 WHERE q.TRADE_FLOW = 'I'
   AND q.MEASURE    = 'Q_tpw'
 GROUP BY m2.CODE
ORDER BY 1, 3;


-- ---------------------------------------------------------------------------
-- Q19. ИТОГО по 10 группам (все товары, входящие в группы): ЭКСПОРТ.
--      Строка "ВСЕГО ПО 10 ГРУППАМ (итого)" таблицы 5 и часть таблицы 6.
--      Запрос без JOIN с классификаторами = сумма по всей таблице,
--      т.к. 100% записей торговли покрываются 10 группами (проверено).
-- ---------------------------------------------------------------------------
SELECT 'ВСЕГО 10 ГРУПП'                                     AS GROUP_CODE,
       'ВСЕГО ПО 10 ГРУППАМ'                                AS GROUP_NAME,
       'C'                                                  AS DATA_TYPE,
       SUM(COALESCE(VALUE_Y2021, 0))                        AS Y2021,
       SUM(COALESCE(VALUE_Y2022, 0))                        AS Y2022,
       SUM(COALESCE(VALUE_Y2023, 0))                        AS Y2023,
       SUM(COALESCE(VALUE_Y2024, 0))                        AS Y2024
  FROM FISHSTAT.TSD_TRADE_VALUE
 WHERE TRADE_FLOW = 'E'
   AND MEASURE    = 'V_USD_1000'
UNION ALL
SELECT 'ВСЕГО 10 ГРУПП'                                     AS GROUP_CODE,
       'ВСЕГО ПО 10 ГРУППАМ'                                AS GROUP_NAME,
       'K'                                                  AS DATA_TYPE,
       SUM(COALESCE(VALUE_Y2021, 0))                        AS Y2021,
       SUM(COALESCE(VALUE_Y2022, 0))                        AS Y2022,
       SUM(COALESCE(VALUE_Y2023, 0))                        AS Y2023,
       SUM(COALESCE(VALUE_Y2024, 0))                        AS Y2024
  FROM FISHSTAT.TSD_TRADE_QUANTITY
 WHERE TRADE_FLOW = 'E'
   AND MEASURE    = 'Q_tpw';


-- ---------------------------------------------------------------------------
-- Q20. ИТОГО по 10 группам: ИМПОРТ.
-- ---------------------------------------------------------------------------
SELECT 'ВСЕГО 10 ГРУПП'                                     AS GROUP_CODE,
       'ВСЕГО ПО 10 ГРУППАМ'                                AS GROUP_NAME,
       'C'                                                  AS DATA_TYPE,
       SUM(COALESCE(VALUE_Y2021, 0))                        AS Y2021,
       SUM(COALESCE(VALUE_Y2022, 0))                        AS Y2022,
       SUM(COALESCE(VALUE_Y2023, 0))                        AS Y2023,
       SUM(COALESCE(VALUE_Y2024, 0))                        AS Y2024
  FROM FISHSTAT.TSD_TRADE_VALUE
 WHERE TRADE_FLOW = 'I'
   AND MEASURE    = 'V_USD_1000'
UNION ALL
SELECT 'ВСЕГО 10 ГРУПП'                                     AS GROUP_CODE,
       'ВСЕГО ПО 10 ГРУППАМ'                                AS GROUP_NAME,
       'K'                                                  AS DATA_TYPE,
       SUM(COALESCE(VALUE_Y2021, 0))                        AS Y2021,
       SUM(COALESCE(VALUE_Y2022, 0))                        AS Y2022,
       SUM(COALESCE(VALUE_Y2023, 0))                        AS Y2023,
       SUM(COALESCE(VALUE_Y2024, 0))                        AS Y2024
  FROM FISHSTAT.TSD_TRADE_QUANTITY
 WHERE TRADE_FLOW = 'I'
   AND MEASURE    = 'Q_tpw';


-- ---------------------------------------------------------------------------
-- Q21. Таблица 6: товарная структура по СТРАНАМ (только ТОП-30 экспортёров).
--      Экспорт, стоимость и вес по каждой из 10 групп для стран из TOP-30
--      (список стран берётся тем же подзапросом, что и в Q2/Q13).
--      Колонки GROUP_CODE/GROUP_NAME/DATA_TYPE + годы; страна — в COUNTRY_CODE.
-- ---------------------------------------------------------------------------
SELECT t.COUNTRY_REPORTER                                   AS COUNTRY_CODE,
       m2.CODE                                              AS GROUP_CODE,
       MAX(m2.NAME_EN)                                      AS GROUP_NAME,
       'C'                                                  AS DATA_TYPE,
       SUM(COALESCE(t.VALUE_Y2021, 0))                      AS Y2021,
       SUM(COALESCE(t.VALUE_Y2022, 0))                      AS Y2022,
       SUM(COALESCE(t.VALUE_Y2023, 0))                      AS Y2023,
       SUM(COALESCE(t.VALUE_Y2024, 0))                      AS Y2024
  FROM FISHSTAT.TSD_TRADE_VALUE t
  JOIN FISHSTAT.REF_COMMODITY    cm ON cm.FAO_CODE = t.COMMODITY
  JOIN FISHSTAT.REL_COMMODITY_MAJOR r ON r.CHILD_ID = cm.ID
  JOIN FISHSTAT.REF_COMMODITY_MAJOR2 m2 ON m2.ID = r.PARENT_ID
 WHERE t.TRADE_FLOW = 'E'
   AND t.MEASURE    = 'V_USD_1000'
   AND t.COUNTRY_REPORTER IN (
        SELECT t2.COUNTRY_REPORTER
          FROM FISHSTAT.TSD_TRADE_VALUE t2
         WHERE t2.TRADE_FLOW = 'E'
           AND t2.MEASURE    = 'V_USD_1000'
         GROUP BY t2.COUNTRY_REPORTER
         ORDER BY SUM(COALESCE(t2.VALUE_Y2024, 0)) DESC, t2.COUNTRY_REPORTER ASC
         FETCH FIRST 30 ROWS ONLY)
 GROUP BY t.COUNTRY_REPORTER, m2.CODE
UNION ALL
SELECT t.COUNTRY_REPORTER                                   AS COUNTRY_CODE,
       m2.CODE                                              AS GROUP_CODE,
       MAX(m2.NAME_EN)                                      AS GROUP_NAME,
       'K'                                                  AS DATA_TYPE,
       SUM(COALESCE(t.VALUE_Y2021, 0))                      AS Y2021,
       SUM(COALESCE(t.VALUE_Y2022, 0))                      AS Y2022,
       SUM(COALESCE(t.VALUE_Y2023, 0))                      AS Y2023,
       SUM(COALESCE(t.VALUE_Y2024, 0))                      AS Y2024
  FROM FISHSTAT.TSD_TRADE_QUANTITY t
  JOIN FISHSTAT.REF_COMMODITY    cm ON cm.FAO_CODE = t.COMMODITY
  JOIN FISHSTAT.REL_COMMODITY_MAJOR r ON r.CHILD_ID = cm.ID
  JOIN FISHSTAT.REF_COMMODITY_MAJOR2 m2 ON m2.ID = r.PARENT_ID
 WHERE t.TRADE_FLOW = 'E'
   AND t.MEASURE    = 'Q_tpw'
   AND t.COUNTRY_REPORTER IN (
        SELECT t2.COUNTRY_REPORTER
          FROM FISHSTAT.TSD_TRADE_VALUE t2
         WHERE t2.TRADE_FLOW = 'E'
           AND t2.MEASURE    = 'V_USD_1000'
         GROUP BY t2.COUNTRY_REPORTER
         ORDER BY SUM(COALESCE(t2.VALUE_Y2024, 0)) DESC, t2.COUNTRY_REPORTER ASC
         FETCH FIRST 30 ROWS ONLY)
 GROUP BY t.COUNTRY_REPORTER, m2.CODE
ORDER BY 1, 2, 4;


-- ---------------------------------------------------------------------------
-- Q22. Таблица 6: товарная структура по СТРАНАМ (ТОП-30 импортёров), импорт.
-- ---------------------------------------------------------------------------
SELECT t.COUNTRY_REPORTER                                   AS COUNTRY_CODE,
       m2.CODE                                              AS GROUP_CODE,
       MAX(m2.NAME_EN)                                      AS GROUP_NAME,
       'C'                                                  AS DATA_TYPE,
       SUM(COALESCE(t.VALUE_Y2021, 0))                      AS Y2021,
       SUM(COALESCE(t.VALUE_Y2022, 0))                      AS Y2022,
       SUM(COALESCE(t.VALUE_Y2023, 0))                      AS Y2023,
       SUM(COALESCE(t.VALUE_Y2024, 0))                      AS Y2024
  FROM FISHSTAT.TSD_TRADE_VALUE t
  JOIN FISHSTAT.REF_COMMODITY    cm ON cm.FAO_CODE = t.COMMODITY
  JOIN FISHSTAT.REL_COMMODITY_MAJOR r ON r.CHILD_ID = cm.ID
  JOIN FISHSTAT.REF_COMMODITY_MAJOR2 m2 ON m2.ID = r.PARENT_ID
 WHERE t.TRADE_FLOW = 'I'
   AND t.MEASURE    = 'V_USD_1000'
   AND t.COUNTRY_REPORTER IN (
        SELECT t2.COUNTRY_REPORTER
          FROM FISHSTAT.TSD_TRADE_VALUE t2
         WHERE t2.TRADE_FLOW = 'I'
           AND t2.MEASURE    = 'V_USD_1000'
         GROUP BY t2.COUNTRY_REPORTER
         ORDER BY SUM(COALESCE(t2.VALUE_Y2024, 0)) DESC, t2.COUNTRY_REPORTER ASC
         FETCH FIRST 30 ROWS ONLY)
 GROUP BY t.COUNTRY_REPORTER, m2.CODE
UNION ALL
SELECT t.COUNTRY_REPORTER                                   AS COUNTRY_CODE,
       m2.CODE                                              AS GROUP_CODE,
       MAX(m2.NAME_EN)                                      AS GROUP_NAME,
       'K'                                                  AS DATA_TYPE,
       SUM(COALESCE(t.VALUE_Y2021, 0))                      AS Y2021,
       SUM(COALESCE(t.VALUE_Y2022, 0))                      AS Y2022,
       SUM(COALESCE(t.VALUE_Y2023, 0))                      AS Y2023,
       SUM(COALESCE(t.VALUE_Y2024, 0))                      AS Y2024
  FROM FISHSTAT.TSD_TRADE_QUANTITY t
  JOIN FISHSTAT.REF_COMMODITY    cm ON cm.FAO_CODE = t.COMMODITY
  JOIN FISHSTAT.REL_COMMODITY_MAJOR r ON r.CHILD_ID = cm.ID
  JOIN FISHSTAT.REF_COMMODITY_MAJOR2 m2 ON m2.ID = r.PARENT_ID
 WHERE t.TRADE_FLOW = 'I'
   AND t.MEASURE    = 'Q_tpw'
   AND t.COUNTRY_REPORTER IN (
        SELECT t2.COUNTRY_REPORTER
          FROM FISHSTAT.TSD_TRADE_VALUE t2
         WHERE t2.TRADE_FLOW = 'I'
           AND t2.MEASURE    = 'V_USD_1000'
         GROUP BY t2.COUNTRY_REPORTER
         ORDER BY SUM(COALESCE(t2.VALUE_Y2024, 0)) DESC, t2.COUNTRY_REPORTER ASC
         FETCH FIRST 30 ROWS ONLY)
 GROUP BY t.COUNTRY_REPORTER, m2.CODE
ORDER BY 1, 2, 4;


-- ---------------------------------------------------------------------------
-- Q23. Таблица 6: итоги по каждой из 10 групп суммарно по всем странам-
--      экспортёрам (строки "10 групп суммарно (итого по каждой позиции)").
--      Совпадает по смыслу с Q17, но выделен отдельно для сборки листа 6.
-- ---------------------------------------------------------------------------
SELECT m2.CODE                                              AS GROUP_CODE,
       MAX(m2.NAME_EN)                                      AS GROUP_NAME,
       'C'                                                  AS DATA_TYPE,
       SUM(COALESCE(v.VALUE_Y2021, 0))                      AS Y2021,
       SUM(COALESCE(v.VALUE_Y2022, 0))                      AS Y2022,
       SUM(COALESCE(v.VALUE_Y2023, 0))                      AS Y2023,
       SUM(COALESCE(v.VALUE_Y2024, 0))                      AS Y2024
  FROM FISHSTAT.TSD_TRADE_VALUE v
  JOIN FISHSTAT.REF_COMMODITY    cm ON cm.FAO_CODE = v.COMMODITY
  JOIN FISHSTAT.REL_COMMODITY_MAJOR r ON r.CHILD_ID = cm.ID
  JOIN FISHSTAT.REF_COMMODITY_MAJOR2 m2 ON m2.ID = r.PARENT_ID
 WHERE v.TRADE_FLOW = 'E'
   AND v.MEASURE    = 'V_USD_1000'
 GROUP BY m2.CODE
UNION ALL
SELECT m2.CODE                                              AS GROUP_CODE,
       MAX(m2.NAME_EN)                                      AS GROUP_NAME,
       'K'                                                  AS DATA_TYPE,
       SUM(COALESCE(q.VALUE_Y2021, 0))                      AS Y2021,
       SUM(COALESCE(q.VALUE_Y2022, 0))                      AS Y2022,
       SUM(COALESCE(q.VALUE_Y2023, 0))                      AS Y2023,
       SUM(COALESCE(q.VALUE_Y2024, 0))                      AS Y2024
  FROM FISHSTAT.TSD_TRADE_QUANTITY q
  JOIN FISHSTAT.REF_COMMODITY    cm ON cm.FAO_CODE = q.COMMODITY
  JOIN FISHSTAT.REL_COMMODITY_MAJOR r ON r.CHILD_ID = cm.ID
  JOIN FISHSTAT.REF_COMMODITY_MAJOR2 m2 ON m2.ID = r.PARENT_ID
 WHERE q.TRADE_FLOW = 'E'
   AND q.MEASURE    = 'Q_tpw'
 GROUP BY m2.CODE
ORDER BY 1, 3;


-- ---------------------------------------------------------------------------
-- Q24. То же, что Q23, но для импорта (для листа 6).
-- ---------------------------------------------------------------------------
SELECT m2.CODE                                              AS GROUP_CODE,
       MAX(m2.NAME_EN)                                      AS GROUP_NAME,
       'C'                                                  AS DATA_TYPE,
       SUM(COALESCE(v.VALUE_Y2021, 0))                      AS Y2021,
       SUM(COALESCE(v.VALUE_Y2022, 0))                      AS Y2022,
       SUM(COALESCE(v.VALUE_Y2023, 0))                      AS Y2023,
       SUM(COALESCE(v.VALUE_Y2024, 0))                      AS Y2024
  FROM FISHSTAT.TSD_TRADE_VALUE v
  JOIN FISHSTAT.REF_COMMODITY    cm ON cm.FAO_CODE = v.COMMODITY
  JOIN FISHSTAT.REL_COMMODITY_MAJOR r ON r.CHILD_ID = cm.ID
  JOIN FISHSTAT.REF_COMMODITY_MAJOR2 m2 ON m2.ID = r.PARENT_ID
 WHERE v.TRADE_FLOW = 'I'
   AND v.MEASURE    = 'V_USD_1000'
 GROUP BY m2.CODE
UNION ALL
SELECT m2.CODE                                              AS GROUP_CODE,
       MAX(m2.NAME_EN)                                      AS GROUP_NAME,
       'K'                                                  AS DATA_TYPE,
       SUM(COALESCE(q.VALUE_Y2021, 0))                      AS Y2021,
       SUM(COALESCE(q.VALUE_Y2022, 0))                      AS Y2022,
       SUM(COALESCE(q.VALUE_Y2023, 0))                      AS Y2023,
       SUM(COALESCE(q.VALUE_Y2024, 0))                      AS Y2024
  FROM FISHSTAT.TSD_TRADE_QUANTITY q
  JOIN FISHSTAT.REF_COMMODITY    cm ON cm.FAO_CODE = q.COMMODITY
  JOIN FISHSTAT.REL_COMMODITY_MAJOR r ON r.CHILD_ID = cm.ID
  JOIN FISHSTAT.REF_COMMODITY_MAJOR2 m2 ON m2.ID = r.PARENT_ID
 WHERE q.TRADE_FLOW = 'I'
   AND q.MEASURE    = 'Q_tpw'
 GROUP BY m2.CODE
ORDER BY 1, 3;
