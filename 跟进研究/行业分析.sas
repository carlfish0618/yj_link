/*** 每天运行的程序 **/
%LET utils_dir = F:\Research\GIT_BACKUP\utils\SAS\修改版本;

%INCLUDE  "D:\Research\CODE\initial_sas.sas";
%INCLUDE  "&utils_dir.\日期_通用函数.sas";
%INCLUDE "&utils_dir.\权重_通用函数.sas";
%INCLUDE "&utils_dir.\交易_通用函数.sas";
%INCLUDE "&utils_dir.\其他_通用函数.sas";
%INCLUDE  "&utils_dir.\组合构建_通用函数.sas";

%LET output_dir = F:\Research\DATA\深交所调研_业绩预告-分行业\output_data\策略;
%LET yj_link_dir = F:\Research\GIT_BACKUP\yj_link\修改版本;

/**************** 模块0: 生成辅助表 **************/
%LET env_start_date = 31dec2008;
%LET index_code = 000300;

/* 外部表1: busdate */
PROC SQL;
	CREATE TABLE busday AS
	SELECT DISTINCT datadate AS end_date
	FROM test.fg_index_dailyreturn
	ORDER BY datadate;
QUIT;

DATA busday(drop = end_date);
	SET busday;
	date = datepart(end_date);
	FORMAT date mmddyy10.;
RUN;
 

PROC SQL;
	CREATE TABLE hqinfo AS
	SELECT datepart(end_date) AS end_date FORMAT mmddyy10.,
		stock_code, close, factor, open, high, low, pre_close, vol, istrade,
		close*factor AS price
	FROM hq.hqinfo
	WHERE type = 'A' AND end_date >= "&env_start_date."d
	ORDER BY end_date, stock_code;
QUIT;


/** 外部表4: 行业和个股映射表 */
/* stock_sector_mapping */
DATA  fg_wind_sector;
	SET bk.fg_wind_sector(keep = end_date stock_code o_code o_name);
	IF datepart(end_date)>= "&env_start_date."d - 40; /* 向前调整最多1个月 */
	date = datepart(end_date);
	FORMAT date mmddyy10.;
RUN; 

/* 时间没有连续，补全时间 */
PROC SQL;
	CREATE TABLE stock_sector_mapping AS
	SELECT stock_code, date 
	FROM 
	(SELECT DISTINCT stock_code
	FROM fg_wind_sector), busday
	where date >= "&env_start_date."d;
QUIT;

PROC SQL;
	CREATE TABLE tmp AS
	SELECT stock_code, date, max(base_date) FORMAT mmddyy10. AS base_date
	FROM
	(SELECT A.*, datepart(B.end_date) FORMAT mmddyy10. AS base_date FROM stock_sector_mapping A LEFT JOIN fg_wind_sector B
	ON A.stock_code = B.stock_code AND datepart(B.end_date) + 40 >= A.date >= datepart(B.end_date)) 
		/* 这里date的涵义是: 下一天生效的行业分类 */
	GROUP BY stock_code, date;
QUIT;

PROC SQL;
	CREATE TABLE stock_sector_mapping AS
	SELECT A.stock_code, A.date AS end_date, o_code AS indus_code LABEL "indus_code", o_name AS indus_name LABEL "indus_name"
	FROM tmp A
	LEFT JOIN fg_wind_sector B
	ON A.stock_code = B.stock_code AND A.base_date = datepart(B.end_date)
	WHERE not missing(base_date)
	ORDER BY A.date, A.stock_code;
QUIT;

PROC SQL;
	DROP TABLE fg_wind_sector,tmp;
QUIT;


/***** 其他辅助表 **************/

/* 辅助表1: 股票信息表 */
PROC SQL;
	CREATE TABLE stock_info_table AS
	SELECT F16_1090 AS stock_code LABEL "stock_code", 
	OB_OBJECT_NAME_1090 AS stock_name LABEL "stock_name",
	F17_1090, 
	F18_1090,
	F19_1090 AS is_delist LABEL "is_delist",
	F6_1090 AS bk LABEL "bk"
	FROM locwind.tb_object_1090
	WHERE F4_1090 = 'A';

	CREATE TABLE not_list_stock AS
	SELECT distinct stock_code
	FROM stock_info_table
	WHERE missing(F17_1090) AND missing(F18_1090);
QUIT;

/* 上市情况 */
DATA stock_info_table(drop = F17_1090 F18_1090);
	SET stock_info_table;
	list_date = input(F17_1090,yymmdd8.);
	delist_date = input(F18_1090,yymmdd8.);
	IF index(stock_name,'ST') THEN is_st = 1;
	ELSE is_st = 0;
	FORMAT list_date delist_date mmddyy10.;
RUN;


/* 辅助表2: 暂停上市的股票 */
PROC SORT DATA = hqinfo;
	BY stock_code end_date;
RUN;
DATA tmp;
	SET hqinfo(keep = stock_code end_date);
	BY stock_code;
	pre_date = lag(end_date);
	IF first.stock_code THEN pre_date = .;
	FORMAT pre_date mmddyy10.;
RUN;


/* 交易日与前一个交易日表 */
DATA busday_pair;
	SET busday;
	pre_date = lag(date);
	FORMAT pre_date mmddyy10.;
RUN;

	
PROC SQL;
	CREATE TABLE tmp2 AS
	SELECT A.*, B.pre_date AS pre_busdate
	FROM tmp A LEFT JOIN busday_pair B
	ON A.end_date = B.date
	ORDER BY A.stock_code, A.end_date;
QUIT;
DATA halt_list_stock(keep = stock_code end_date pre_date);
	SET tmp2;
	IF not missing(pre_date) AND not missing(pre_busdate) AND pre_date ~= pre_busdate;
RUN;

PROC SQL;
	DROP TABLE tmp, tmp2, busday_pair;
QUIT;

/** 3: A股股票 */
PROC SQL;
	CREATE TABLE a_stock_list AS
	SELECT distinct stock_code
	FROM hqinfo
	ORDER BY stock_code;
QUIT;


PROC SQL;
	CREATE TABLE tmp AS
	SELECT *
	FROM a_stock_list
	WHERE stock_code NOT IN
	(SELECT stock_code FROM not_list_stock);
QUIT;
DATA a_stock_list;
	SET tmp;
RUN;


/*************************************************** 模块1: 生成调仓股票池************************/
%INCLUDE  "&yj_link_dir.\1-全业绩链事件_生成事件信号.sas";
%INCLUDE  "&yj_link_dir.\2-全业绩链事件_生成交易信号.sas";


/* 生成调仓股票池 */
DATA stock_signal(drop = report_date next_a_report_date next_f_report_date f_signal);
	SET forecast_signal;
	end_date = report_date;
	FORMAT end_date mmddyy10.;
	sell_date = min(next_a_report_date, next_f_report_date);
	signal = f_signal;
	FORMAT sell_date mmddyy10.;
RUN;
%adjust_date(busday_table = busday, raw_table = stock_signal, colname = sell_date); 

DATA stock_signal(drop = adj_sell_date sell_date_is_busday);
	SET stock_signal;
	sell_date = adj_sell_date;
RUN;


/**　!!统计：持有到卖出之间的时间间隔　*/
%map_date_to_index(busday_table=busday, raw_table= stock_signal, date_col_name=end_date, raw_table_edit=stock_signal2)
DATA stock_signal2;
	SET stock_signal2(rename = (date_index = buy_date_index));
RUN;

%map_date_to_index(busday_table=busday, raw_table= stock_signal2, date_col_name=sell_date, raw_table_edit=stock_signal2)
DATA stock_signal2;
	SET stock_signal2(rename = (date_index = sell_date_index));
	intval = sell_date_index - buy_date_index;
RUN;
PROC SORT DATA = stock_signal2;
	BY descending intval;
RUN;


/* 作图 */

PROC SQL;
	CREATE TABLE stat AS
	SELECT A.*, round(A.nobs/B.t_nobs*100,0.01) AS pct
	FROM 
	(
		SELECT intval, count(1) AS nobs
		FROM stock_signal2
		WHERE sell_date ~= "&tail_date."d
		GROUP BY intval
	)A, 
	(
		SELECT count(1) AS t_nobs
		FROM stock_signal2
		WHERE sell_date ~= "&tail_date."d
	)B
	ORDER BY intval;
QUIT;
DATA stat;
	SET stat;
	RETAIN accum_pct 0;
	accum_pct + pct;
RUN;     /* 82%的股票从买入到卖出时间间隔在60个交易日内 */


/******************************************* 模块2: 策略回测-调仓组合确定 ******************************/
/** 测试不同的策略 */
/* d/w/m 分别对应有事件调整/每周/每月的调仓频率 */
/** 策略：持有到正式财报发布 */


/***　Step1: 构造股票池 **/

PROC SQL;
	CREATE TABLE tmp AS
	SELECT A.*, B.date
	FROM a_stock_list A, busday B
	WHERE "15dec2009"d <= date
	ORDER BY stock_code, date;
QUIT;

/** 删除未上市或退市记录 **/

PROC SQL;
	CREATE TABLE tmp2 AS
	SELECT A.*, B.list_date, B.delist_date, B.is_st
	FROM tmp A LEFT JOIN stock_info_table B
	ON A.stock_code = B.stock_code
	LEFT JOIN halt_list_stock C
	ON A.stock_code = C.stock_code
	ORDER BY stock_code, date;
QUIT;
DATA tmp2;
	SET tmp2;
	IF NOT missing(delist_date) AND date > delist_date THEN delete; /* 已退市 */
	IF NOT missing(list_date) AND date <= list_date THEN delete; /* 未上市 */
	IF missing(list_date) THEN delete; /* 从未上市 */
	IF is_st THEN delete;  /** 扣除ST **/
RUN;

/** 删除临时暂停上市的股票 */
PROC SQL;
	CREATE TABLE tmp AS
	SELECT A.*, B.end_date, B.pre_date AS start_date
	FROM tmp2 A LEFT JOIN halt_list_stock B
	ON A.stock_code = B.stock_code
	ORDER BY A.stock_code;
QUIT;   /* 当一个股票反复出现暂停，重新上市，可能产生多条连接记录 */
DATA tmp;
	SET tmp;
	IF not missing(start_date) AND not missing(end_Date) AND start_date <=date <=end_date THEN delete; /* 暂停上市区间内无数据(含头尾) */
RUN;
PROC SORT DATA = tmp;
	BY stock_code date;
RUN; 
PROC SORT DATA = tmp NODUPKEY OUT =merge_stock_pool(keep = stock_code date);
	BY stock_code date;
RUN;

PROC SQL;
	DROP TABLE tmp, tmp2;
QUIT;

%map_date_to_index(busday_table=busday, raw_table=merge_stock_pool, date_col_name=date, raw_table_edit=merge_stock_pool);
%map_date_to_index(busday_table=busday, raw_table=stock_signal, date_col_name=end_date, raw_table_edit=stock_signal);

PROC SQL;
	CREATE TABLE merge_stock_pool2 AS
	SELECT A.*, B.signal, B.end_date AS signal_date, B.date_index AS index_signal_date, B.sell_date AS sell_date
	FROM merge_stock_pool A LEFT JOIN stock_signal B
	ON A.stock_code = B.stock_code AND A.date = B.end_date
	ORDER BY A.stock_code, A.date;
QUIT;


/** 持有到卖出日 */
DATA merge_stock_pool2(drop= r_hold2 r_sell_date);
	SET merge_stock_pool2;
	BY stock_code;
	RETAIN r_hold2 0;  
	RETAIN r_sell_date .;

	IF first.stock_code THEN DO;
		r_hold2 = 0;
		r_sell_date = .;
	END;
	/* 策略：持有到正式财报 */
	IF  signal = 1 THEN DO;
		r_hold2 = 1;
		r_sell_date = sell_date;
	END;
	ELSE DO;
		IF r_hold2 = 1 AND date >= r_sell_date THEN  DO;
			r_hold2 = 0;
		END;
	END;
	FORMAT r_sell_date mmddyy10.;	
	hold2 = r_hold2; /** 信号认定为在end_date，也就是当天收盘后产生。 */
RUN;

/*DATA tt;*/
/*	SET merge_stock_pool_2;*/
/*	IF hold2 = 1;*/
/*RUN;*/


/* 考虑无法买入/卖出的情况 */
PROC SQL;
	CREATE TABLE tmp AS
	SELECT A.*, B.close, B.open, B.pre_close, B.high, B.low, B.vol
	FROM merge_stock_pool2 A LEFT JOIN hqinfo B
	ON A.stock_code = B.stock_code AND A.date = B.end_date
	ORDER BY A.stock_code, A.date;
QUIT;

DATA merge_stock_pool(drop = close open pre_close high low vol);
	SET tmp;
	IF date = list_date THEN not_trade = 1; /* 上市首日，不可买入 */
	IF missing(vol) OR vol = 0 THEN not_trade = 1;
	ELSE IF close = high AND close = low AND close = open AND close > pre_close THEN not_trade = 1;  /* 涨停 */
	ELSE IF close = high AND close = low AND close = open AND close < pre_close THEN not_trade = 1; /* 跌停 */
	ELSE not_trade = 0;
RUN;


DATA merge_stock_pool(drop = rr_hold2 list_date delist_date signal_date index_signal_date);
	SET merge_stock_pool;
	BY stock_code;
	RETAIN rr_hold2 0;   /* 记录前一天(考虑买入/卖出仙之后的)持有情况 */
	IF first.stock_code THEN DO;
		rr_hold2 = 0;
	END;
	
	/* 持有到期策略 */
	IF rr_hold2 = 0 AND hold2 = 1 THEN DO ;   /* 首次买入 */
		IF not_trade = 1 THEN DO;
			f_hold2 = 0;  /* 无法买入 */
		END;
		ELSE DO;
			f_hold2 = 1;
		END;
	END;
	/* 需要卖出 */
	ELSE IF rr_hold2 = 1 AND hold2 = 0 THEN DO; 
		IF not_trade = 1 THEN DO;   /* 无法卖出，继续持有 */
			f_hold2 = 1;  
		END;
		ELSE DO;
			f_hold2 = 0;
		END;
	END;
	ELSE DO;
		f_hold2 = hold2;
	END;
	IF last.stock_code AND date = delist_date THEN f_hold2 = 0; /* 如果已经是最后一个交易日，且恰好是退市日，则强制卖出 */
	rr_hold2 = f_hold2;
RUN;


/* 暂时不予处理无法买入/卖出的情况*/
DATA merge_stock_pool;
	SET merge_stock_pool2;
	f_hold2 = hold2;
RUN;


/********************************************** 模块3：策略回测-生成指数及表现评价 *******************/
%LET indus_code = all;  /* FG19- TMT, FG08医药 */
%LET s_name = &indus_code._d;
%LET filename = &s_name..xls;


/** Step1; 准备相关表格 */

/* Step1-1: 回测日期 */
DATA test_busdate;
	SET busday;
	IF  "01jan2010"d <= date <= "28feb2015"d;
RUN;

/*** Step1-2: 调仓日期: 周频率(周二) **/
DATA adj_busdate(rename = (date = end_date));
	SET busday;
	IF "15dec2009"d <= date <= "28feb2015"d;
	year = year(date);
	month = month(date);
	weekday = weekday(date);
RUN;

PROC SORT DATA = adj_busdate;
	BY year month end_date;
RUN;
DATA adj_busdate(keep = end_date);
	SET adj_busdate;
	/* 周五 */
/*	IF weekday = 6;   */
RUN;

/**　Step2: 确定调仓组合和权重 */
DATA test_stock_pool(drop = f_hold2);
	SET merge_stock_pool(keep = date stock_code f_hold2);
	IF f_hold2 = 1;
	weight = 1;
RUN;

PROC SORT DATA = test_stock_pool;
	BY date;
RUN;


/** 与方旻的数据进行对比 */
PROC SQL;	
	CREATE TABLE tmp AS
	SELECT end_date, count(1) AS nobs
	FROM tinysoft.fg_surp_stock
	GROUP BY end_date
	ORDER BY end_date;
QUIT;

PROC SQL;
	CREATE TABLE stat AS
	SELECT A.date, A.nobs, B.nobs AS nobs_f
	FROM 
	(
		SELECT date, count(1) AS nobs
		FROM test_stock_pool
		GROUP BY date) A
	LEFT JOIN tmp B
	ON A.date = datepart(B.end_date)
	WHERE date >= "01dec2014"d
	ORDER BY A.date;
QUIT;

PROC SQL;
	CREATE TABLE tmp AS
	SELECT A.*, B.stock_code AS stock_code_b, C.stock_code AS stock_code_c
	FROM tinysoft.fg_surp_stock A LEFT JOIN test_stock_pool B
	ON A.stock_code = B.stock_code AND B.date = datepart(A.end_date)
	LEFT JOIN test_stock_pool C
	ON A.stock_code = C.stock_code AND C.date - datepart(A.end_date) =1
	WHERE missing(stock_code_b) AND missing(stock_code_c) AND datepart(A.end_date) >= "01dec2014"d AND datepart(A.end_date) <= "25feb2015"d
	ORDER BY stock_code, end_date;
QUIT;

PROC SQL;
	CREATE TABLE stat4 AS
	SELECT *
	FROM test_stock_pool
	WHERE stock_code = "000400"
	ORDER BY date;
QUIT;

PROC SQL;
	CREATE TABLE stat2 AS
	SELECT *
	FROM forecast_signal
	WHERE stock_code = "603601"
	ORDER BY report_date;
QUIT;


PROC SQL;
	CREATE TABLE stat3 AS
	SELECT *
	FROM earning_forecast_merge
	WHERE stock_code = "002736"
	ORDER BY report_date;
QUIT;


PROC SQL;
	CREATE TABLE stat2 AS
	SELECT *
	FROM merge_stock_pool
	WHERE stock_code = "002736"
	ORDER BY date;
QUIT;


DATA subset_raw;
	SET test_stock_pool;
	IF date < "01nov2013"d;
RUN;

/*** 2013/11/1日开始使用方旻数据库中的数据 **/
/** 用方旻数据库中的数据 **/
PROC SQL;
	CREATE TABLE subset AS
	SELECT datepart(end_date) AS date FORMAT mmddyy10., stock_code, 1 AS weight
	FROM tinysoft.fg_surp_stock
	WHERE datepart(end_date) >= "01nov2013"d
	ORDER BY date;
QUIT;

DATA test_stock_pool;
	SET subset_raw subset;
RUN;

/* 只选出特定行业的股票 */
PROC SQL;
	CREATE TABLE tmp AS
	SELECT A.*, B.o_code, B.o_name
	FROM test_stock_pool A LEFT JOIN stock_sector_mapping B
	ON A.stock_code = B.stock_code AND A.date = B.end_date
	ORDER BY A.date, A.stock_code;
QUIT;
DATA test_stock_pool;
	SET tmp;
/*	IF o_code = "&indus_code.";*/
RUN;



/*** Step3: 确定每日组合 */
%gen_adjust_pool(stock_pool=test_stock_pool, adjust_date_table=adj_busdate, move_date_forward=0, output_stock_pool=test_stock_pool);
%neutralize_weight(stock_pool = test_stock_pool, output_stock_pool = test_stock_pool);
DATA stock_pool_backup;
	SET test_stock_pool;
RUN;



%gen_daily_pool(stock_pool=test_stock_pool, test_period_table=test_busdate, adjust_date_table=adj_busdate, output_stock_pool=test_stock_pool);
%cal_stock_wt_ret(daily_stock_pool=test_stock_pool, adjust_date_table=adj_busdate, output_stock_pool=test_stock_pool);
%cal_portfolio_ret(daily_stock_pool=test_stock_pool, output_daily_summary=&s_name._daily);
%trading_summary(daily_stock_pool=test_stock_pool, adjust_date_table=adj_busdate, output_stock_trading=&s_name._trade_d, output_daily_trading=&s_name._trade_s);

LIBNAME myxls  "&output_dir.\&filename.";
	DATa myxls.daily;
		SET &s_name._daily;
	RUN;

/*	DATA myxls.trade_d;*/
/*		SET &s_name._trade_d;*/
/*	RUN;*/
	DATA myxls.trade_s;
		SET &s_name._trade_s;
	RUN;

LIbNAME myxls clear;
