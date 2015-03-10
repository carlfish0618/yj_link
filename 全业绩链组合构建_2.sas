%LET index_code = 000300;
%LET env_start_date = 20dec2005;



/*外部表1： 交易日 */
 PROC SQL;
	CREATE TABLE busday AS
	SELECT DISTINCT effective_date AS end_date
	FROM tinysoft.index_info
	ORDER BY end_date;
QUIT;

DATA busday(drop = end_date);
	SET busday;
	IF not missing(end_date);
	date = datepart(end_date);
	FORMAT date mmddyy10.;
RUN;
 

/** 外部表2-3: hqinfo/benchmark_hqinfo **/
/* 为了优化效率，提取行情子表 */
 DATA hqinfo(drop = end_date rename = (date = end_date)) benchmark_hqinfo(drop = end_date rename = (date = end_date));
        SET hq.hqinfo(keep = end_date stock_code close factor type open high low pre_close vol istrade);
        date = datepart(end_date);
        FORMAT date mmddyy10.;
       	price = close * factor;
        IF price <= 0 THEN price = .;
        IF type = 'A' AND end_date >= "&env_start_date."d  THEN OUTPUT hqinfo;
        ELSE IF type = 'S' AND stock_code = "&index_code." AND end_date >= "&env_start_date."d THEN OUTPUT benchmark_hqinfo;
RUN;

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
	SELECT A.stock_code, A.date AS end_date, o_code, o_name
	FROM tmp A
	LEFT JOIN fg_wind_sector B
	ON A.stock_code = B.stock_code AND A.base_date = datepart(B.end_date)
	WHERE not missing(base_date)
	ORDER BY A.date, A.stock_code;
QUIT;



PROC SQL;
	DROP TABLE fg_wind_sector,tmp;
QUIT;


/* 外部表5：指数成分股（缺800) */
DATA index_300_500;
	SET tinysoft.index_info(keep = index_code end_date effective_date stock_code weight);
	IF index_code IN ("000300","000905");
	end_date = datepart(end_date);
	effective_date = datepart(effective_date);   /* 这里effective_date有缺失的 */
	FORMAT end_date effective_date mmddyy10.;
RUN;
DATA index_cyb;
	SET tinysoft.index_info_sz(keep = index_code end_date effective_date stock_code weight);
	IF index_code IN ("399006");
	end_date = datepart(end_date);
	effective_date = datepart(effective_date);
	FORMAT end_date effective_date mmddyy10.;
RUN;


/* 补充文汉自己生成的，800和cyb900指数 */
DATA tmp2;
	SET test.index_info_800(keep = index_code effective_date stock_code weight);
	IF index_code IN ("000906","cyb900");
	effective_date = datepart(effective_date);
	FORMAT effective_date mmddyy10.;
RUN;
/* 增加end_date */
PROC SORT DATA = busday;
	BY date;
RUN;

DATA busday_pair;
	SET busday;
	pre_date = lag(date);
	FORMAT pre_date mmddyy10.;
RUN;
PROC SQL;
	CREATE TABLE tmp3 AS
	SELECT A.*, B.pre_date AS end_date
	FROM tmp2 A LEFT JOIN busday_pair B
	ON A.effective_date = B.date
	ORDER BY index_code, effective_date,stock_code;
QUIT;

DATA index_component;
	SET index_300_500 index_cyb tmp3;
RUN;

/* 有些effective_date缺失 */
PROC SQL;
	CREATE TABLE tmp AS
	SELECT A.*, B.date AS effective_date_2
	FROM index_component A LEFT JOIN busday_pair B
	ON A.end_date = B.pre_date
	ORDER BY A.index_code, A.end_date;
QUIT;
DATA index_component(drop = effective_date_2);
	SET tmp;
	IF missing(effective_date) THEN effective_date = effective_date_2;
RUN;
PROC SQL;
	DROP TABLE index_300_500, index_cyb, tmp2, tmp3, busday_pair, tmp;
QUIT;


/** 外部表6: 指数行情表（全收益，自己生成) **/
/** 包括: 300/500/800/399006/cyb900 **/
PROC SQL;
	CREATE TABLE tmp AS
	SELECT A.*, B.close, B.pre_close
	FROM index_component A LEFT JOIN hqinfo B
	ON A.end_date = B.end_date AND A.stock_code = B.stock_code
	WHERE A.end_date >= "&env_start_date."d
	ORDER BY A.index_code, A.end_date, A.stock_code;
QUIT;

 /* 美的集团，2013/9/17没有收盘价格，因为9/18才刚上市。但是其在指数中9/17日有权重 */
DATA tmp;
	SET tmp;
	daily_ret = (close-pre_close)/pre_close * 100; 
RUN;


PROC SQL;
	CREATE TABLE tmp2 AS
	SELECT A.*, B.daily_ret
	FROM
	(
	SELECT index_code, end_date, count(1) AS nobs
	FROM tmp
	GROUP index_code, end_date) A
	LEFT JOIN
	(
	SELECT index_code, effective_date, sum(daily_ret * weight/100) AS daily_ret
	FROM tmp
	GROUP BY index_code, effective_date) B
	ON A.index_code = B.index_code AND A.end_date  = B.effective_date  /* !!!!!!!有错 */
	ORDER BY A.index_code, A.end_date;
QUIT;


DATA benchmark_hqinfo_qsy(rename = (index_code = stock_code));  /* 全收益 */
	SET tmp2;
	BY index_code;
	RETAIN close 1000;
	IF first.index_code THEN DO;
		close = 1000;
		daily_ret = 0;
	END;
	close = close * (1+daily_ret/100);
	price = close;
RUN;

PROC SQL;
	DROP TABLE tmp, tmp2;
QUIT;

DATA benchmark_hqinfo_2;
	SET benchmark_hqinfo_qsy;
	IF stock_code = "&index_code.";
RUN;

/** 外部表：行业指数收益，自己计算。行业分类为基准指数中的分类 */
DATA tt;
	SET busday;
RUN;
PROC SORT DATA = tt;
	BY date;
RUN;
DATA tt;
	SET tt;
	pre_date = lag(date);
	FORMAT pre_date mmddyy10.;
RUN;

DATA sub_component;
	SET index_component;
	IF index_code = "cyb900";
RUN;



PROC SQL;
		CREATE TABLE tmp AS
		SELECT A.*, E.pre_date, (B.close*B.factor) AS price, (C.close*C.factor) AS pre_price, (B.close*B.factor-C.close*C.factor)/(C.close*C.factor)*100 AS daily_ret
		FROM sub_component A
		LEFT JOIN tt E
		ON A.effective_date = E.date
		LEFT JOIN hqinfo B
		ON A.effective_date = B.end_date AND A.stock_code = B.stock_code
		LEFT JOIN hqinfo C
		ON E.pre_date = C.end_date AND A.stock_code = C.stock_code
		WHERE A.end_date >= "&env_start_date."d
		ORDER BY A.end_date, A.stock_code;
QUIT;

/* 行业分类 */
PROC SQL;
	CREATE TABLE tmp2 AS
	SELECT A.*, B.o_code, B.o_name
	FROM tmp A LEFT JOIN stock_sector_mapping B
	ON A.stock_code = B.stock_code AND A.end_date = B.end_date
	ORDER BY A.end_date, A.stock_code;
QUIT;


PROC SQL;
	CREATE TABLE tmp3 AS
	SELECT o_code, o_name, effective_date AS end_date, sum(daily_ret * weight/100) AS daily_ret, count(1) AS nobs
	FROM tmp2
	GROUP BY o_code,o_name, effective_date
	ORDER BY o_code, o_name;
QUIT;


DATA index_hqinfo(rename = (o_code = stock_code));  /* 全收益 */
	SET tmp3;
	BY o_code;
	RETAIN close 1000;
	IF first.o_code THEN DO;
		close = 1000;
		daily_ret = 0;
	END;
	close = close * (1+daily_ret/100);
	price = close;
RUN;

PROC SQL;
	DROP TABLE tt, sub_component, tmp, tmp2, tmp3;
QUIT;



/***** 其他辅助表 **************/

/* 辅助表1: 所有A股 */
PROC SQL;
	CREATE TABLE a_stock_list AS
	SELECt distinct stock_code
	FROM hqinfo;
QUIT;

/* 辅助表2: 股票信息表 */
/* 排除未上市股票 */
PROC SQL;
	CREATE TABLE stock_info_table AS
	SELECT F16_1090 AS stock_code, OB_OBJECT_NAME_1090 AS stock_name,  F17_1090, F18_1090, F19_1090 AS is_delist, F6_1090 AS bk
	FROM locwind.tb_object_1090
	WHERE F4_1090 = 'A';

	CREATE TABLE not_list_stock AS
	SELECT distinct stock_code
	FROM stock_info_table
	WHERE missing(F17_1090) AND missing(F18_1090);
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

/* 上市情况 */
DATA stock_info_table(drop = F17_1090 F18_1090);
	SET stock_info_table;
	list_date = input(F17_1090,yymmdd8.);
	delist_date = input(F18_1090,yymmdd8.);
	IF index(stock_name,'ST') THEN is_st = 1;
	ELSE is_st = 0;
	FORMAT list_date delist_date mmddyy10.;
RUN;



/* 辅助表3: 暂停上市的股票 */
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


/****** 构造全业绩股票池 **/
PROC SQL;
	CREATE TABLE tmp AS
	SELECT A.*, B.date
	FROM a_stock_list A, busday B
	WHERE "01jan2007"d <= date
	ORDER BY stock_code, date;
QUIT;

/** 删除未上市或退市记录 **/

PROC SQL;
	CREATE TABLE tmp2 AS
	SELECT A.*, B.list_date, B.delist_date
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
	IF start_date <=date <=end_date THEN delete; /* 暂停上市区间内无数据(含头尾) */
RUN;
PROC SORT DATA = tmp;
	BY stock_code date;
RUN; 
PROC SORT DATA = tmp NODUPKEY OUT =merge_stock_pool;
	BY stock_code date;
RUN;

PROC SQL;
	DROP TABLE tmp, tmp2;
QUIT;




/* 3种策略：
(1) 持有至退出信号
(2) 固定持有天数
(3) 卖出信号+最大持有期
(4) 财报发布后退出
*/

/*%INCLUDE  "D:\Research\DATA\yjyg_link\code_20140827\全业绩链事件整理_2.sas";*/

%map_date_to_index(busday_table=busday, raw_table=merge_signal, date_col_name=date, raw_table_edit=merge_signal);
%map_date_to_index(busday_table=busday, raw_table=merge_stock_pool, date_col_name=date, raw_table_edit=merge_stock_pool);

PROC SQL;
	CREATE TABLE merge_stock_pool_2 AS
	SELECT A.*, B.signal, B.tar_cmp, B.date AS signal_date, B.date_index AS index_signal_date
	FROM merge_stock_pool A LEFT JOIN merge_signal B
	ON A.stock_code = B.stock_code AND A.date = B.date
	ORDER BY A.stock_code, A.date;
QUIT;


/* !!!!!!!!!!!!!!! 需要把所有的信号都调整为日末调整后的，不要设定为日初的。(该步骤尚未进行） ****/
DATA merge_stock_pool_2(drop= r_hold r_hold2 r_hold3 r_hold4 r_signal_date r_index_signal_date r_hold3 r_signal_date3 r_index_signal_date3 dif_day dif_day3);
	SET merge_stock_pool_2;
	BY stock_code;
	RETAIN r_hold 0; 
	RETAIN r_hold2 0;  /* 持有到期 */
	RETAIN r_hold3 0; 
	RETAIN r_hold4 0;
	RETAIN r_signal_date .;
	RETAIN r_index_signal_date .;
	RETAIN r_signal_date3 .;
	RETAIN r_index_signal_date3 .;


	IF first.stock_code THEN DO;
		r_hold = 0;
		r_hold2 = 0;
		r_hold3 = 0;
		r_hold4 = 0;
		r_signal_date = .;
		r_index_signal_date = .;
		r_signal_date3 = .;
		r_index_signal_date3 = .;
	END;
	
	/** 第一种策略：持有到卖出信号 */
	/* 生成明天的信号 */
	hold = r_hold;  /* 用昨天的信号构造买入与否信号 */
	IF  tar_cmp = 1 AND signal = 1 THEN r_hold = 1;  /* 买入信号发生，待下一个交易日开盘后买入 */
*	ELSE IF tar_cmp = 1 AND signal = 0 THEN r_hold = 0;
*	ELSE IF tar_cmp = 0 AND signal = 0 THEN r_hold = 0;  /* tar_cmp = 0 and signal = 1 信号不变 */
	ELSE IF r_hold = 1 AND signal = 0 THEN r_hold = 0;  /* 卖出信号 */
	

	/* 第二种策略：持有固定天数 */
	hold2 = r_hold2;
	IF  tar_cmp = 1 AND signal = 1 THEN DO;
		r_hold2 = 1;
		r_signal_date = signal_date;
		r_index_signal_date = index_signal_date;
	END;
	ELSE DO;
*		IF NOT missing(r_index_signal_date) AND date_index - r_index_signal_date < 60 THEN r_hold2 = 1;
		IF r_hold2 = 1 AND date_index - r_index_signal_date >= 60 THEN  r_hold2 = 0;
	END;
	dif_day = date_index - r_index_signal_date;
	FORMAT r_signal_date mmddyy10.;
	

	/* 第三种策略: 卖出信号+最长持有时间 */
	hold3 = r_hold3;
	IF  tar_cmp = 1 AND signal = 1 THEN DO;
		r_hold3 = 1;
		r_signal_date3 = signal_date;
		r_index_signal_date3 = index_signal_date;
	END;
	ELSE DO;
		IF r_hold3 = 1 AND signal = 0 THEN r_hold3 = 0;
		ELSE IF r_hold3 = 1 AND date_index - r_index_signal_date3 >= 60 THEN  r_hold3 = 0;
	END;
	dif_day3 = date_index - r_index_signal_date3;
	FORMAT r_signal_date3 mmddyy10.;

	/* 第四种策略: 财报发布后，卖出 */
	hold4 = r_hold4;
	IF tar_cmp = 1 AND signal = 1 THEN r_hold4 = 1;  /* 买入信号发生，待下一个交易日开盘后买入 */
	ELSE IF r_hold4 = 1 AND (signal = 0 OR tar_cmp = 0) THEN r_hold4 = 0;  /* 卖出信号 */
	
RUN;

DATA merge_stock_pool;
	SET merge_stock_pool_2;
RUN;


/* 暂时不予处理 */
/* 考虑无法买入/卖出的情况 */
PROC SQL;
	CREATE TABLE tmp AS
	SELECT A.*, B.close, B.open, B.pre_close, B.high, B.low, B.vol
	FROM merge_stock_pool_2 A LEFT JOIN hqinfo B
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



DATA merge_stock_pool(drop = rr_hold rr_hold2 rr_hold3 rr_hold4 list_date delist_date start_date end_date signal_date index_signal_date);
	SET merge_stock_pool;
	BY stock_code;
	RETAIN rr_hold .;
	RETAIN rr_hold2 .;
	RETAIN rr_hold3 .;
	RETAIN rr_hold4 .;
	IF first.stock_code THEN DO;
		rr_hold = .;
		rr_hold2 = .;
		rr_hold3 = .;
		rr_hold4 = .;
	END;
	IF (rr_hold = 0 OR missing(rr_hold)) AND hold = 1 THEN DO ;   /* 首次买入 */
		IF not_trade = 1 THEN DO;
			f_hold = 0;  /* 无法买入 */
		END;
		ELSE DO;
			f_hold = 1;
		END;
	END;
	/* 需要卖出 */
	ELSE IF rr_hold = 1 AND hold = 0 THEN DO; 
		IF not_trade = 1 THEN DO; 
			f_hold = 1;  
		END;
		ELSE DO;
			f_hold = 0;
		END;
	END;
	ELSE DO;
		f_hold = hold;
	END;
	IF last.stock_code AND date = delist_date THEN f_hold = 0; /* 如果已经是最后一个交易日，且恰好是退市日，则强制卖出 */
	rr_hold = f_hold;

	/* 持有到期策略 */
	IF (rr_hold2 = 0 OR missing(rr_hold2)) AND hold2 = 1 THEN DO ;   /* 首次买入 */
		IF not_trade = 1 THEN DO;
			f_hold2 = 0;  /* 无法买入 */
		END;
		ELSE DO;
			f_hold2 = 1;
		END;
	END;
	/* 需要卖出 */
	ELSE IF rr_hold2 = 1 AND hold2 = 0 THEN DO; 
		IF not_trade = 1 THEN DO; 
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

	/* 卖出信号+最大持有期 */
	IF (rr_hold3 = 0 OR missing(rr_hold3)) AND hold3 = 1 THEN DO ;   /* 首次买入 */
		IF not_trade = 1 THEN DO;
			f_hold3 = 0;  /* 无法买入 */
		END;
		ELSE DO;
			f_hold3 = 1;
		END;
	END;
	/* 需要卖出 */
	ELSE IF rr_hold3 = 1 AND hold3 = 0 THEN DO; 
		IF not_trade = 1 THEN DO; 
			f_hold3 = 1;  
		END;
		ELSE DO;
			f_hold3 = 0;
		END;
	END;
	ELSE DO;
		f_hold3 = hold3;
	END;
	IF last.stock_code AND date = delist_date THEN f_hold3 = 0; /* 如果已经是最后一个交易日，且恰好是退市日，则强制卖出 */
	rr_hold3 = f_hold3;

	/* 正是财报卖出 */
	IF (rr_hold4 = 0 OR missing(rr_hold4)) AND hold4 = 1 THEN DO ;   /* 首次买入 */
		IF not_trade = 1 THEN DO;
			f_hold4 = 0;  /* 无法买入 */
		END;
		ELSE DO;
			f_hold4 = 1;
		END;
	END;
	/* 需要卖出 */
	ELSE IF rr_hold4 = 1 AND hold4 = 0 THEN DO; 
		IF not_trade = 1 THEN DO; 
			f_hold4 = 1;  
		END;
		ELSE DO;
			f_hold4 = 0;
		END;
	END;
	ELSE DO;
		f_hold4 = hold4;
	END;
	IF last.stock_code AND date = delist_date THEN f_hold4 = 0; /* 如果已经是最后一个交易日，且恰好是退市日，则强制卖出 */
	rr_hold4 = f_hold4;
RUN;




/** 只选择股票池中的股票 */
/** 选择交易日和调整股票池日期最近的 */
PROC SQL;
	CREATE TABLE adj_busdate AS
	SELECT date, max(adj_date) AS adj_date FORMAT mmddyy10.
	FROM 
	(SELECT A.date, B.adj_date
	FROM busday A LEFT JOIN 
	(SELECT distinct datepart(end_date) AS adj_date FROM tinysoft.fg_uni_hs300) B
	ON A.date > adj_date)
	GROUP BY date
	ORDER BY date;
QUIT;

PROC SQL;
	CREATE TABLE tmp AS
	SELECT A.*,B.adj_date, C.stock_code AS stock_code_c
	FROM merge_stock_pool A LEFT JOIN adj_busdate B
	ON A.date = B.date
	LEFT JOIN  tinysoft.fg_uni_hs300 C
	ON A.stock_code = C.stock_code AND datepart(C.end_date) = B.adj_date
	ORDER BY A.stock_code, A.date;
QUIT;

DATA merge_stock_pool;
	SET tmp;
	f_hold = hold;
	f_hold2 = hold2;
	f_hold3 = hold3;
	f_hold4 = hold4;
	IF stock_code ~= stock_code_c THEN DO;
		f_hold = 0;
		f_hold2 = 0;
		f_hold3 = 0;
		f_hold4 = 0;
	END;
RUN;


/****************** 策略回测 ***/

/* 调仓时间 */
DATA adj_busdate(rename = (date = end_date));
	SET busday;
	IF "01jan2008"d <= date <= "20sep2014"d;
	year = year(date);
	month = month(date);
	weekday = weekday(date);
RUN;
PROC SORT DATA = adj_busdate;
	BY year month end_date;
RUN;
DATA adj_busdate(keep = end_date);
	SET adj_busdate;
/*	BY year month;*/
/*	IF last.month;*/
/*	IF weekday = 6;*/
RUN;

/* 测试时间 */
DATA test_busdate;
	SET busday;
	IF "01jan2008"d <= date <= "20sep2014"d;
RUN;


/** 测试不同的策略 */
/* yz: 表示选择“预增”组 */
/* s1/s2/s3/s4 分别对应4种不同的退出策略 */
/* d/w/m 分别对应每日/每周/每月的调仓频率 */
/* I: 表示行业中性处理 */
/* subset: 表示股票池 */
%LET output_dir = D:\Research\DATA\yjyg_link\output_data_20140922;
%LET s_name = yz_s4_d;
%LET filename = &s_name..xls;
/*PROC SQL;*/
/*	CREATE TABLE all_stock_pool AS*/
/*	SELECT A.*, B.ob_object_name_1090 AS stock_name*/
/*	FROM merge_stock_pool A LEFT JOIN locwind.TB_OBJECT_1090 B*/
/*	ON A.stock_code = B.f16_1090*/
/*	WHERE f_hold = 1 AND b.f4_1090='A'*/
/*	ORDER BY A.stock_code, A.date;*/
/*QUIT;*/

DATA test_stock_pool(drop = f_hold4);
	SET merge_stock_pool(keep = date stock_code f_hold4);
	IF f_hold4 = 1;
	weight = 1;
	is_bm = 0;
RUN;

PROC SORT DATa = test_stock_pool;
	BY date;
RUN;



%gen_adjust_pool(stock_pool=test_stock_pool, adjust_date_table=adj_busdate, move_date_forward=1, output_stock_pool=test_stock_pool);
%fill_in_index(stock_pool=test_stock_pool,adjust_date_table=adj_busdate, all_max_weight=1, ind_max_weight=0.05, output_stock_pool=test_stock_pool);
/*%adjust_to_sector_neutral(stock_pool=test_stock_pool, adjust_date_table=adj_busdate, max_within_indus=0.2, output_stock_pool=test_stock_pool);*/
%fill_stock(stock_pool=test_stock_pool, adjust_date_table = adj_busdate, output_stock_pool=test_stock_pool);
%gen_daily_pool(stock_pool=test_stock_pool, test_period_table=test_busdate, adjust_date_table=adj_busdate, output_stock_pool=test_stock_pool);
%cal_stock_wt_ret(daily_stock_pool=test_stock_pool, adjust_date_table=adj_busdate, output_stock_pool=test_stock_pool);
/*%cal_stock_wt_ret_loop(daily_stock_pool=test_stock_pool, output_stock_pool=test_stock_pool);*/
%cal_portfolio_ret(daily_stock_pool=test_stock_pool, output_daily_summary=&s_name._daily);
%trading_summary(daily_stock_pool=test_stock_pool, adjust_date_table=adj_busdate, output_stock_trading=&s_name._trade_d, output_daily_trading=&s_name._trade_s);
%eval_pfmance(daily_summary=&s_name._daily, daily_trading=&s_name._trade_s,  test_period_table=test_busdate, output_daily_summary=&s_name._daily, output_pfmance_summary=&s_name._summary);
%exposure_analyze(daily_stock_pool = test_stock_pool, output_daily_exposure_t = &s_name._exposure);
%cal_holding_list(stock_trading_table =&s_name._trade_d , test_period_table = test_busdate, output_holding_list = &s_name._holding_list);

LIBNAME myxls  "&output_dir.\&filename.";
	DATa myxls.daily;
		SET &s_name._daily;
	RUN;

	DATA myxls.summary;
		SET &s_name._summary;
	RUN;
/*	DATA myxls.trade_d;*/
/*		SET &s_name._trade_d;*/
/*	RUN;*/
	DATA myxls.trade_s;
		SET &s_name._trade_s;
	RUN;

	DATA myxls.holding_list;
		SET &s_name._holding_list;
	RUN;

	DATA myxls.exposure;
		SET &s_name._exposure;
	RUN;

LIbNAME myxls clear;



/****** 回测：业绩因子 **/
%LET output_dir = D:\Research\DATA\yjyg_link\output_data_20140915;
%LET s_name = f_300;
%LET filename = &s_name..xls;


PROC SQL;
	CREATE TABLE sur_stock AS
	SELECT stock_code, datepart(end_date) FORMAT mmddyy10. AS date, 1 AS weight, 0 AS is_bm
	FROM score.fg_hs300_factor
	WHERE sur_pre_eps > 0
	ORDER BY date;
QUIT;

DATA test_stock_pool;
	SET sur_stock;
RUN;

%gen_adjust_pool(stock_pool=test_stock_pool, adjust_date_table=adj_busdate, move_date_forward=0, output_stock_pool=test_stock_pool);
%fill_in_index(stock_pool=test_stock_pool,adjust_date_table=adj_busdate, all_max_weight=1, ind_max_weight=0.05, output_stock_pool=test_stock_pool);
/*%adjust_to_sector_neutral(stock_pool=test_stock_pool, adjust_date_table=adj_busdate, max_within_indus=0.2, output_stock_pool=test_stock_pool);*/
%fill_stock(stock_pool=test_stock_pool, output_stock_pool=test_stock_pool);
%gen_daily_pool(stock_pool=test_stock_pool, test_period_table=test_busdate, adjust_date_table=adj_busdate, output_stock_pool=test_stock_pool);
%cal_stock_wt_ret(daily_stock_pool=test_stock_pool, adjust_date_table=adj_busdate, output_stock_pool=test_stock_pool);
/*%cal_stock_wt_ret_loop(daily_stock_pool=test_stock_pool, output_stock_pool=test_stock_pool);*/
%cal_portfolio_ret(daily_stock_pool=test_stock_pool, output_daily_summary=&s_name._daily);
%trading_summary(daily_stock_pool=test_stock_pool, adjust_date_table=adj_busdate, output_stock_trading=&s_name._trade_d, output_daily_trading=&s_name._trade_s);
%eval_pfmance(daily_summary=&s_name._daily, daily_trading=&s_name._trade_s, test_period_table=test_busdate, output_daily_summary=&s_name._daily, output_pfmance_summary=&s_name._summary);

LIBNAME myxls  "&output_dir.\&filename.";
	DATa myxls.daily;
		SET &s_name._daily;
	RUN;

	DATA myxls.summary;
		SET &s_name._summary;
	RUN;
/*	DATA myxls.trade_d;*/
/*		SET &s_name._trade_d;*/
/*	RUN;*/
	DATA myxls.trade_s;
		SET &s_name._trade_s;
	RUN;

	DATA myxls.holding_list;
		SET &s_name._holding_list;
	RUN;

	DATA myxls.exposure;
		SET &s_name._exposure;
	RUN;

LIbNAME myxls clear;


/** 回测: 优化结果 **/
PROC IMPORT OUT= WORK.opti_no_pool 
            DATAFILE= "D:\Research\DATA\yjyg_link\opti_pool.xls" 
            DBMS=EXCEL REPLACE;
     RANGE="无限制$"; 
     GETNAMES=YES;
     MIXED=NO;
     SCANTEXT=YES;
     USEDATE=YES;
     SCANTIME=YES;
RUN;
DATA opti_no_pool(drop=date2);
	SET opti_no_pool(rename = (date = date2));
	date = input(date2, yymmdd10.);
	FORMAT date mmddyy10.;
RUN;

PROC IMPORT OUT= WORK.opti_yes_pool 
            DATAFILE= "D:\Research\DATA\yjyg_link\opti_pool.xls" 
            DBMS=EXCEL REPLACE;
     RANGE="有限制$"; 
     GETNAMES=YES;
     MIXED=NO;
     SCANTEXT=YES;
     USEDATE=YES;
     SCANTIME=YES;
RUN;

%LET output_dir = D:\Research\DATA\yjyg_link\output_data_20140915;
%LET s_name = opti_300;
%LET filename = &s_name..xls;

DATA test_stock_pool;
	SET opti_no_pool(keep = code date weight rename = (code = stock_code));
	is_bm = 1;
RUN;

%gen_adjust_pool(stock_pool=test_stock_pool, adjust_date_table=adj_busdate, move_date_forward=0, output_stock_pool=test_stock_pool);
%gen_daily_pool(stock_pool=test_stock_pool, test_period_table=test_busdate, adjust_date_table=adj_busdate, output_stock_pool=test_stock_pool);
%cal_stock_wt_ret(daily_stock_pool=test_stock_pool, adjust_date_table=adj_busdate, output_stock_pool=test_stock_pool);
DATA test_stock_pool;
	SET test_stock_pool;
	add_in = 0;
RUN;
/*%cal_stock_wt_ret_loop(daily_stock_pool=test_stock_pool, output_stock_pool=test_stock_pool);*/
%cal_portfolio_ret(daily_stock_pool=test_stock_pool, output_daily_summary=&s_name._daily);
%trading_summary(daily_stock_pool=test_stock_pool, adjust_date_table=adj_busdate, output_stock_trading=&s_name._trade_d, output_daily_trading=&s_name._trade_s);
%eval_pfmance(daily_summary=&s_name._daily, daily_trading=&s_name._trade_s,  test_period_table=test_busdate, output_daily_summary=&s_name._daily, output_pfmance_summary=&s_name._summary);

LIBNAME myxls  "&output_dir.\&filename.";
	DATa myxls.daily;
		SET &s_name._daily;
	RUN;

	DATA myxls.summary;
		SET &s_name._summary;
	RUN;
/*	DATA myxls.trade_d;*/
/*		SET &s_name._trade_d;*/
/*	RUN;*/
	DATA myxls.trade_s;
		SET &s_name._trade_s;
	RUN;

	DATA myxls.holding_list;
		SET &s_name._holding_list;
	RUN;

	DATA myxls.exposure;
		SET &s_name._exposure;
	RUN;

LIbNAME myxls clear;

/*** 季节影响 **/
DATA season_effect;
	SET yz_s1_300_i_daily;
	year = year(date);
	month = month(date);
RUN;
PROC SQL;
	CREATE TABLE season_effect_stat AS
	SELECT year, month, sum(alpha_tc) AS alpha_tc
	FROM season_effect
	GROUP BY year, month;
QUIT;

PROC TRANSPOSE DATA = season_effect_stat prefix = month OUT = season_effect_stat;
	VAR alpha_tc;
	BY year;
	ID month;
RUN;


PROC SQL;
	CREATe TABLE stat1 AS
	SELECT date, sum(close_wt) AS close_wt
	FROM test_stock_pool
	GROUP BY date;
QUIT;

PROC SQL;
	CREATE TABLE stat1 AS
	SELECT distinct stock_code, o_name
	FROM index_hqinfo
	ORDER BY stock_code;
QUIT;
