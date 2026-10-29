-- REF_COMMODITY 1771 видов товаров классификации и кодировки ISSCFC (Commodity)
create table FISHSTAT.REF_COMMODITY
(
    ID       VARCHAR(20) not null                          -- здесь и далее во всех таблицах, внутренний ID таблицы для индексирования (формат 00000001)
        primary key,
    FAO_CODE VARCHAR(20)                                   -- Код товара ISSCFC (формат 034, 034.1, 034.1.1, 034.1.5.2.11)
        constraint UNQ_REF_COMMODITY_FAO_CODE
            unique,
    NAME_EN  VARCHAR(400),                                 -- Имя товара в классификации ISSCFC на английском
    NAME_FR  VARCHAR(400),                                 -- здесь и далее во всех таблицах, поля с языками кроме английского (_EN) игнорируются
    NAME_ES  VARCHAR(400),                                  
    NAME_AR  VARCHAR(400),
    NAME_ZH  VARCHAR(400),
    NAME_RU  VARCHAR(400),
    EBXID    BIGINT                                        -- здесь и далее во всех таблицах, EBXID - внутренний код (игнорируется)
        constraint UNQ_REF_COMMODITY_EBXID
            unique
);

-- REF_COMMODITY_MAJOR2 10 основных групп товаров (FAO major group)
create table FISHSTAT.REF_COMMODITY_MAJOR2
(
    ID      VARCHAR(20) not null
        primary key,
    NAME_EN VARCHAR(200),                                  -- Имя товарной группы в классификации FAO на английском
    NAME_FR VARCHAR(200),
    NAME_ES VARCHAR(200),
    NAME_AR VARCHAR(200),
    NAME_ZH VARCHAR(200),
    NAME_RU VARCHAR(200),
    EBXID   BIGINT
        constraint UNQ_REF_COMMODITY_MAJOR2_EBXID
            unique,
    CODE    VARCHAR(20)                                    -- Код товарной группы FAO (формат 1,2, ... ,A)
        constraint UNQ_REF_COMMODITY_MAJOR2_CODE
            unique
);

-- REF_COUNTRY_REPORTER список 225 стран
create table FISHSTAT.REF_COUNTRY_REPORTER
(
    ID               VARCHAR(20) not null
        primary key,
    UN_CODE          VARCHAR(3)                            -- код ООН страны (используется в основной таблице поле COUNTRY_REPORTER, 3 цифры)
        constraint UNQ_REF_COUNTRY_REPORTER_UN_CODE
            unique,
    ISO_2_CODE       VARCHAR(2),                           -- не используется
    NAME_EN          VARCHAR(80),                          -- Название страны в стандарте ООН
    NAME_FR          VARCHAR(80),
    NAME_ES          VARCHAR(80),
    NAME_AR          VARCHAR(80),
    NAME_ZH          VARCHAR(80),
    NAME_RU          VARCHAR(80),
    OFFICIAL_NAME_EN VARCHAR(80),                          -- не используется
    OFFICIAL_NAME_FR VARCHAR(80),
    OFFICIAL_NAME_ES VARCHAR(80),
    OFFICIAL_NAME_AR VARCHAR(80),
    OFFICIAL_NAME_ZH VARCHAR(80),
    OFFICIAL_NAME_RU VARCHAR(80),
    ISO_3_CODE       VARCHAR(3),                           -- не используется
    ALPHA12_CODE     VARCHAR(12),                          -- не используется
    EBXID            BIGINT
        constraint UNQ_REF_COUNTRY_REPORTER_EBXID
            unique
);


-- REF_MEASURE 11 единиц измерения (в базе используются только V_USD_1000 для стоимости товара и Q_tpw для веса товара)
create table FISHSTAT.REF_MEASURE
(
    ID              VARCHAR(20) not null
        primary key,
    CODE            VARCHAR(60) not null                   -- код единицы измерения (используется в основной таблице поле MEASURE)
        constraint UNQ_REF_MEASURE_CODE
            unique,
    NAME_EN         VARCHAR(80),                           -- имя единицы измерения 
    NAME_FR         VARCHAR(80),
    NAME_ES         VARCHAR(80),
    NAME_AR         VARCHAR(80),
    NAME_ZH         VARCHAR(80),
    NAME_RU         VARCHAR(80),
    UNIT            VARCHAR(20) not null,                  -- не используется
    UNIT_MULTIPLIER VARCHAR(20) not null,                  -- не используется
    SHORT_NAME      VARCHAR(30)                            -- не используется
);


-- направление торговли (экспорт/импорт)
create table FISHSTAT.REF_TRADE_FLOW
(
    ID         VARCHAR(20) not null
        primary key,
    EBXID      BIGINT
        constraint UNQ_REF_TRADE_FLOW_EBXID
            unique,
    NAME_EN    VARCHAR(80),                                -- название направления (Import/Export, Reexport игнорируется)
    NAME_FR    VARCHAR(80),
    NAME_ES    VARCHAR(80),
    NAME_AR    VARCHAR(80),
    NAME_ZH    VARCHAR(80),
    NAME_RU    VARCHAR(80),
    ALPHA_CODE VARCHAR(1)                                  -- код направления ("I" или "E", "R" (Reexport) игнорируется)
        constraint UNQ_REF_TRADE_FLOW_ALPHA_CODE
            unique
);

-- REL_COMMODITY_MAJOR реляционная таблица наполнения групп REF_COMMODITY_MAJOR2 списком товаров REF_COMMODITY 
-- коду PERENT_ID (группа REF_COMMODITY_MAJOR2.CODE) соответствует несколько CHILD_ID (товары REF_COMMODITY.ID)
create table FISHSTAT.REL_COMMODITY_MAJOR
(
    ID        VARCHAR(20) not null
        primary key,
    PARENT_ID VARCHAR(20)                                  -- код группы REF_COMMODITY_MAJOR2.CODE
        constraint REL_COMMODITY_MAJOR_PARENT_FK
            references FISHSTAT.REF_COMMODITY_MAJOR2
            on delete cascade,
    CHILD_ID  VARCHAR(20)                                  -- код товара REF_COMMODITY.ID
        constraint REL_COMMODITY_MAJOR_CHILD_FK 
            references FISHSTAT.REF_COMMODITY
            on delete cascade
);

create index FISHSTAT.REL_COMMODITY_MAJOR_IDX
    on FISHSTAT.REL_COMMODITY_MAJOR (PARENT_ID, CHILD_ID);

-- TSD_TRADE_QUANTITY основная таблица статистики торговли "страна-мир" по весу товаров
create table FISHSTAT.TSD_TRADE_QUANTITY
(
    ID               VARCHAR(20) not null
        primary key,
    COUNTRY_REPORTER VARCHAR(3),                           -- код страны REF_COUNTRY_REPORTER.UN_CODE
    COMMODITY        VARCHAR(20),                          -- код товара REF_COMMODITY.FAO_CODE
    TRADE_FLOW       VARCHAR(1),                           -- направление торговли REF_TRADE_FLOW.ALPHA_CODE
    MEASURE          VARCHAR(20),                          -- код единицы измерения REF_MEASURE.CODE (всегда "Q_tpw" для TSD_TRADE_QUANTITY)
    VALUE_Y1976      DOUBLE,                               -- c VALUE_Y1976 до VALUE_Y2024 - поля данных в единице измерения MEASURE
    SYMBOL_Y1976     VARCHAR(20),                          -- с SYMBOL_Y1976 до SYMBOL_Y2024 - статус достоверности данных соответствующего поля VALUE_Yxxxx в формате Eurostat, эти поля игнорируются и все значения полей VALUE_Yxxxx принимаются за абсолютно точные
    VALUE_Y1977      DOUBLE,
    SYMBOL_Y1977     VARCHAR(20),
    VALUE_Y1978      DOUBLE,
    SYMBOL_Y1978     VARCHAR(20),
    VALUE_Y1979      DOUBLE,
    SYMBOL_Y1979     VARCHAR(20),
    VALUE_Y1980      DOUBLE,
    SYMBOL_Y1980     VARCHAR(20),
    VALUE_Y1981      DOUBLE,
    SYMBOL_Y1981     VARCHAR(20),
    VALUE_Y1982      DOUBLE,
    SYMBOL_Y1982     VARCHAR(20),
    VALUE_Y1983      DOUBLE,
    SYMBOL_Y1983     VARCHAR(20),
    VALUE_Y1984      DOUBLE,
    SYMBOL_Y1984     VARCHAR(20),
    VALUE_Y1985      DOUBLE,
    SYMBOL_Y1985     VARCHAR(20),
    VALUE_Y1986      DOUBLE,
    SYMBOL_Y1986     VARCHAR(20),
    VALUE_Y1987      DOUBLE,
    SYMBOL_Y1987     VARCHAR(20),
    VALUE_Y1988      DOUBLE,
    SYMBOL_Y1988     VARCHAR(20),
    VALUE_Y1989      DOUBLE,
    SYMBOL_Y1989     VARCHAR(20),
    VALUE_Y1990      DOUBLE,
    SYMBOL_Y1990     VARCHAR(20),
    VALUE_Y1991      DOUBLE,
    SYMBOL_Y1991     VARCHAR(20),
    VALUE_Y1992      DOUBLE,
    SYMBOL_Y1992     VARCHAR(20),
    VALUE_Y1993      DOUBLE,
    SYMBOL_Y1993     VARCHAR(20),
    VALUE_Y1994      DOUBLE,
    SYMBOL_Y1994     VARCHAR(20),
    VALUE_Y1995      DOUBLE,
    SYMBOL_Y1995     VARCHAR(20),
    VALUE_Y1996      DOUBLE,
    SYMBOL_Y1996     VARCHAR(20),
    VALUE_Y1997      DOUBLE,
    SYMBOL_Y1997     VARCHAR(20),
    VALUE_Y1998      DOUBLE,
    SYMBOL_Y1998     VARCHAR(20),
    VALUE_Y1999      DOUBLE,
    SYMBOL_Y1999     VARCHAR(20),
    VALUE_Y2000      DOUBLE,
    SYMBOL_Y2000     VARCHAR(20),
    VALUE_Y2001      DOUBLE,
    SYMBOL_Y2001     VARCHAR(20),
    VALUE_Y2002      DOUBLE,
    SYMBOL_Y2002     VARCHAR(20),
    VALUE_Y2003      DOUBLE,
    SYMBOL_Y2003     VARCHAR(20),
    VALUE_Y2004      DOUBLE,
    SYMBOL_Y2004     VARCHAR(20),
    VALUE_Y2005      DOUBLE,
    SYMBOL_Y2005     VARCHAR(20),
    VALUE_Y2006      DOUBLE,
    SYMBOL_Y2006     VARCHAR(20),
    VALUE_Y2007      DOUBLE,
    SYMBOL_Y2007     VARCHAR(20),
    VALUE_Y2008      DOUBLE,
    SYMBOL_Y2008     VARCHAR(20),
    VALUE_Y2009      DOUBLE,
    SYMBOL_Y2009     VARCHAR(20),
    VALUE_Y2010      DOUBLE,
    SYMBOL_Y2010     VARCHAR(20),
    VALUE_Y2011      DOUBLE,
    SYMBOL_Y2011     VARCHAR(20),
    VALUE_Y2012      DOUBLE,
    SYMBOL_Y2012     VARCHAR(20),
    VALUE_Y2013      DOUBLE,
    SYMBOL_Y2013     VARCHAR(20),
    VALUE_Y2014      DOUBLE,
    SYMBOL_Y2014     VARCHAR(20),
    VALUE_Y2015      DOUBLE,
    SYMBOL_Y2015     VARCHAR(20),
    VALUE_Y2016      DOUBLE,
    SYMBOL_Y2016     VARCHAR(20),
    VALUE_Y2017      DOUBLE,
    SYMBOL_Y2017     VARCHAR(20),
    VALUE_Y2018      DOUBLE,
    SYMBOL_Y2018     VARCHAR(20),
    VALUE_Y2019      DOUBLE,
    SYMBOL_Y2019     VARCHAR(20),
    VALUE_Y2020      DOUBLE,
    SYMBOL_Y2020     VARCHAR(20),
    VALUE_Y2021      DOUBLE,
    SYMBOL_Y2021     VARCHAR(20),
    VALUE_Y2022      DOUBLE,
    SYMBOL_Y2022     VARCHAR(20),
    VALUE_Y2023      DOUBLE,
    SYMBOL_Y2023     VARCHAR(20),
    VALUE_Y2024      DOUBLE,
    SYMBOL_Y2024     VARCHAR(20),
    constraint TSD_TRADE_QUANTITY_KEYS_IDX
        unique (COUNTRY_REPORTER, COMMODITY, TRADE_FLOW, MEASURE)
);

create index FISHSTAT.TSD_TRADE_QUANTITY_COMMODITY_IDX
    on FISHSTAT.TSD_TRADE_QUANTITY (COMMODITY);

create index FISHSTAT.TSD_TRADE_QUANTITY_COUNTRY_REPORTER_IDX
    on FISHSTAT.TSD_TRADE_QUANTITY (COUNTRY_REPORTER);

create index FISHSTAT.TSD_TRADE_QUANTITY_MEASURE_IDX
    on FISHSTAT.TSD_TRADE_QUANTITY (MEASURE);

create index FISHSTAT.TSD_TRADE_QUANTITY_TRADE_FLOW_IDX
    on FISHSTAT.TSD_TRADE_QUANTITY (TRADE_FLOW);

-- TSD_TRADE_VALUE основная таблица статистики торговли "страна-мир" по стоимости товаров
create table FISHSTAT.TSD_TRADE_VALUE
(
    ID               VARCHAR(20) not null
        primary key,
    COUNTRY_REPORTER VARCHAR(3),                           -- код страны REF_COUNTRY_REPORTER.UN_CODE
    COMMODITY        VARCHAR(20),                          -- код товара REF_COMMODITY.FAO_CODE
    TRADE_FLOW       VARCHAR(1),                           -- направление торговли REF_TRADE_FLOW.ALPHA_CODE
    MEASURE          VARCHAR(20),                          -- код единицы измерения REF_MEASURE.CODE (всегда "V_USD_1000" для TSD_TRADE_VALUE)
    VALUE_Y1976      DOUBLE,                               -- c VALUE_Y1976 до VALUE_Y2024 - поля данных в единице измерения MEASURE
    SYMBOL_Y1976     VARCHAR(20),                          -- с SYMBOL_Y1976 до SYMBOL_Y2024 - статус достоверности данных соответствующего поля VALUE_Yxxxx в формате Eurostat, эти поля игнорируются и все значения полей VALUE_Yxxxx принимаются за абсолютно точные
    VALUE_Y1977      DOUBLE,
    SYMBOL_Y1977     VARCHAR(20),
    VALUE_Y1978      DOUBLE,
    SYMBOL_Y1978     VARCHAR(20),
    VALUE_Y1979      DOUBLE,
    SYMBOL_Y1979     VARCHAR(20),
    VALUE_Y1980      DOUBLE,
    SYMBOL_Y1980     VARCHAR(20),
    VALUE_Y1981      DOUBLE,
    SYMBOL_Y1981     VARCHAR(20),
    VALUE_Y1982      DOUBLE,
    SYMBOL_Y1982     VARCHAR(20),
    VALUE_Y1983      DOUBLE,
    SYMBOL_Y1983     VARCHAR(20),
    VALUE_Y1984      DOUBLE,
    SYMBOL_Y1984     VARCHAR(20),
    VALUE_Y1985      DOUBLE,
    SYMBOL_Y1985     VARCHAR(20),
    VALUE_Y1986      DOUBLE,
    SYMBOL_Y1986     VARCHAR(20),
    VALUE_Y1987      DOUBLE,
    SYMBOL_Y1987     VARCHAR(20),
    VALUE_Y1988      DOUBLE,
    SYMBOL_Y1988     VARCHAR(20),
    VALUE_Y1989      DOUBLE,
    SYMBOL_Y1989     VARCHAR(20),
    VALUE_Y1990      DOUBLE,
    SYMBOL_Y1990     VARCHAR(20),
    VALUE_Y1991      DOUBLE,
    SYMBOL_Y1991     VARCHAR(20),
    VALUE_Y1992      DOUBLE,
    SYMBOL_Y1992     VARCHAR(20),
    VALUE_Y1993      DOUBLE,
    SYMBOL_Y1993     VARCHAR(20),
    VALUE_Y1994      DOUBLE,
    SYMBOL_Y1994     VARCHAR(20),
    VALUE_Y1995      DOUBLE,
    SYMBOL_Y1995     VARCHAR(20),
    VALUE_Y1996      DOUBLE,
    SYMBOL_Y1996     VARCHAR(20),
    VALUE_Y1997      DOUBLE,
    SYMBOL_Y1997     VARCHAR(20),
    VALUE_Y1998      DOUBLE,
    SYMBOL_Y1998     VARCHAR(20),
    VALUE_Y1999      DOUBLE,
    SYMBOL_Y1999     VARCHAR(20),
    VALUE_Y2000      DOUBLE,
    SYMBOL_Y2000     VARCHAR(20),
    VALUE_Y2001      DOUBLE,
    SYMBOL_Y2001     VARCHAR(20),
    VALUE_Y2002      DOUBLE,
    SYMBOL_Y2002     VARCHAR(20),
    VALUE_Y2003      DOUBLE,
    SYMBOL_Y2003     VARCHAR(20),
    VALUE_Y2004      DOUBLE,
    SYMBOL_Y2004     VARCHAR(20),
    VALUE_Y2005      DOUBLE,
    SYMBOL_Y2005     VARCHAR(20),
    VALUE_Y2006      DOUBLE,
    SYMBOL_Y2006     VARCHAR(20),
    VALUE_Y2007      DOUBLE,
    SYMBOL_Y2007     VARCHAR(20),
    VALUE_Y2008      DOUBLE,
    SYMBOL_Y2008     VARCHAR(20),
    VALUE_Y2009      DOUBLE,
    SYMBOL_Y2009     VARCHAR(20),
    VALUE_Y2010      DOUBLE,
    SYMBOL_Y2010     VARCHAR(20),
    VALUE_Y2011      DOUBLE,
    SYMBOL_Y2011     VARCHAR(20),
    VALUE_Y2012      DOUBLE,
    SYMBOL_Y2012     VARCHAR(20),
    VALUE_Y2013      DOUBLE,
    SYMBOL_Y2013     VARCHAR(20),
    VALUE_Y2014      DOUBLE,
    SYMBOL_Y2014     VARCHAR(20),
    VALUE_Y2015      DOUBLE,
    SYMBOL_Y2015     VARCHAR(20),
    VALUE_Y2016      DOUBLE,
    SYMBOL_Y2016     VARCHAR(20),
    VALUE_Y2017      DOUBLE,
    SYMBOL_Y2017     VARCHAR(20),
    VALUE_Y2018      DOUBLE,
    SYMBOL_Y2018     VARCHAR(20),
    VALUE_Y2019      DOUBLE,
    SYMBOL_Y2019     VARCHAR(20),
    VALUE_Y2020      DOUBLE,
    SYMBOL_Y2020     VARCHAR(20),
    VALUE_Y2021      DOUBLE,
    SYMBOL_Y2021     VARCHAR(20),
    VALUE_Y2022      DOUBLE,
    SYMBOL_Y2022     VARCHAR(20),
    VALUE_Y2023      DOUBLE,
    SYMBOL_Y2023     VARCHAR(20),
    VALUE_Y2024      DOUBLE,
    SYMBOL_Y2024     VARCHAR(20),
    constraint TSD_TRADE_VALUE_KEYS_IDX
        unique (COUNTRY_REPORTER, COMMODITY, TRADE_FLOW, MEASURE)
);

create index FISHSTAT.TSD_TRADE_VALUE_COMMODITY_IDX
    on FISHSTAT.TSD_TRADE_VALUE (COMMODITY);

create index FISHSTAT.TSD_TRADE_VALUE_COUNTRY_REPORTER_IDX
    on FISHSTAT.TSD_TRADE_VALUE (COUNTRY_REPORTER);

create index FISHSTAT.TSD_TRADE_VALUE_MEASURE_IDX
    on FISHSTAT.TSD_TRADE_VALUE (MEASURE);

create index FISHSTAT.TSD_TRADE_VALUE_TRADE_FLOW_IDX
    on FISHSTAT.TSD_TRADE_VALUE (TRADE_FLOW);

