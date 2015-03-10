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

/** 构建每日的组合（优化组合每月优化一次）*/
PROC SQL;
	CREATE TABLE month_date AS
	SELECT distinct date
	FROM opti_no_pool
	ORDER BY date;
QUIT;
DATA month_date;
	SET month_date;
	prev_date = lag(date);
	FORMAT prev_date mmddyy10.;
	IF not missing(prev_date) AND not missing(date);
RUN;


PROC SQL;
	CREATE TABLE busday_month AS
	SELECT A.*, B.prev_date FORMAT mmddyy10. AS adj_date
	FROM busday A LEFT JOIN month_date B
	ON B.prev_date < A.date <= B.date
	WHERE  "01feb2008"d <= A.date;
QUIT;

DATA busday_month;
	SET busday_month;
	IF not missing(adj_date);
RUN;   /* 截至2014-08-20 */


PROC SQL;
	CREATE TABLE opti_no_pool_all AS
	SELECT A.date, B.code AS stock_code, B.Weight 
	FROM busday_month A LEFT JOIN opti_no_pool B
	ON A.adj_date = B.date
	ORDER BY A.date, B.weight desc;
QUIT;


PROC SQL;
	CREATE TABLE opti_yes_pool_all AS
	SELECT A.date, B.code AS stock_code, B.Weight 
	FROM busday_month A LEFT JOIN opti_yes_pool B
	ON A.adj_date = B.date
	ORDER BY A.date, B.weight desc;
QUIT;


%LET output_dir = D:\Research\DATA\yjyg_link\output_date_20140827;
%LET filename = opti_yes_pool_300.xls;
PROC SQL;
	CREATE TABLE all_stock_pool AS
	SELECT A.*, B.ob_object_name_1090 AS stock_name
	FROM opti_yes_pool_all A LEFT JOIN locwind.TB_OBJECT_1090 B
	ON A.stock_code = B.f16_1090
	WHERE b.f4_1090='A'
	ORDER BY A.date, A.stock_code;
QUIT;

DATA all_stock_pool;
	SET all_stock_pool(keep = stock_code stock_name date weight rename = (date = end_date));
	end_time = dhms(end_date,0,0, time());
	FORMAT end_date mmddyy10.;
	FORMAT end_time datetime20.;
RUN;

DATA test_stock_pool_mdf;
	SET all_stock_pool(keep = stock_code end_date stock_name weight rename = (end_date = date));
	is_bm = 0;
	IF "01feb2008"d <= date <= "20aug2014"d;
RUN;

%cal_weighted_return(stock_pool=test_stock_pool_mdf);
%eval_pfmance();


LIBNAME myxls  "&output_dir.\&filename.";
	DATa myxls.link_day;
		SET summary_day;
	RUN;

	DATA myxls.link_stat;
		SET summary_stat;
	RUN;
LIbNAME myxls clear;


/********** 直接根据因子得分来构建等权组合 *********/

%LET output_dir = D:\Research\DATA\yjyg_link\output_date_20140827;
%LET filename = f_pool_300.xls;

PROC SQL;
	CREATE TABLE sur_stock AS
	SELECT stock_code, datepart(end_date) FORMAT mmddyy10. AS date, 1 AS weight, 0 AS is_bm
	FROM score.fg_hs300_factor
	WHERE sur_pre_eps > 0
	ORDER BY date;
QUIT;

/* 往后移动一个交易日，构建下一个交易日的组合 */
PROC SQL;
	CREATE TABLE sur_stock2 AS
	SELECT A.*, B.date AS effective_date
	FROM sur_stock A LEFT JOIN busday_pair B
	ON A.date = B.pre_date
	ORDER BY effective_date;
QUIT;
DATA sur_stock;
	SET sur_stock2(drop = date rename = (effective_date = date));
RUN;



DATA test_stock_pool;
	SET sur_stock;
RUN;

/** 为了与优化组合进行对比，假设每月调仓一次 */
/* 选取月初组合作为整个月组合 */
DATA tt_stock;
	SET sur_stock;
	year = year(date);
	month = month(date);
RUN;
PROC SORT DATA = tt_stock;
	BY year month date;
RUN;

PROC SQL;
	CREATE TABLE tmp AS
	SELECT year, month, min(date) FORMAT mmddyy10. AS date
	FROM tt_stock
	GROUP BY year, month;
QUIT;

DATA tmp2;
	SET busday;
	IF "01feb2008"d <= date <= "20aug2014"d;
	year = year(date);
	month = month(date);
RUN;

PROC SQL;
	CREATE TABLE test_stock_pool AS
	SELECT A.date, C.stock_code, C.weight, C.is_bm
	FROM tmp2 A LEFT JOIN tmp B
	ON A.year = B.year AND A.month = B.month
	LEFT JOIN tt_stock C
	ON B.date = C.date
	ORDER BY A.date, C.weight desc;
QUIT;


%fill_in_index(my_library=work, stock_pool=test_stock_pool, busday_table=busday, start_date="01jan2007"d, 
		all_max_weight=1, ind_max_weight=0.05, edit_stock_pool=test_stock_pool_mdf);

%adjust_to_sector_neutral(my_library=work, stock_pool=test_stock_pool, start_date="01jan2007"d,
	max_within_indus=0.2, edit_stock_pool=test_stock_pool_mdf);

%fill_stock(my_library=work, stock_pool=test_stock_pool_mdf, edit_stock_pool=test_stock_pool_mdf);

DATA test_stock_pool_mdf;
	SET test_stock_pool_mdf;
	IF "01feb2008"d <= date <= "20aug2014"d;
RUN;

%cal_weighted_return(stock_pool=test_stock_pool_mdf);
%eval_pfmance();


LIBNAME myxls  "&output_dir.\&filename.";
	DATa myxls.link_day;
		SET summary_day;
	RUN;

	DATA myxls.link_stat;
		SET summary_stat;
	RUN;
LIbNAME myxls clear;

/************ 季节效应分析 **/
DATA season_effect;
	SET summary_day;
	year = year(date);
	month = month(date);
RUN;
PROC SORT DATA = season_effect;
	BY year month date;
RUN;
DATA first_date;
	SET season_effect;
	BY year month;
	If first.month;
RUN;
PROC SQL;
	CREATE TABLE season_effect_stat AS
	SELECT A.*, B.pos_t, round((A.accum_alpha - B.pos_t*0.7),0.01) AS alpha_tc
	FROM 
	(SELECT year, month, sum(daily_alpha) AS accum_alpha 
	FROM season_effect
	GROUP BY year, month) A
	LEFT JOIN first_date B
	ON A.year = B.year AND A.month = B.month
	ORDER BY A.year, A.month;
QUIT;

PROC TRANSPOSE DATA = season_effect_stat prefix = month OUT = season_effect_stat;
	VAR alpha_tc;
	BY year;
	ID month;
RUN;


/** 绩效分析 **/
/**把组合往前移一天　*/
PROC SQL;
	CREATE TABLE pef_stock AS
	SELECT A.date, A.stock_code,A.weight, B.pre_date
	FROM test_stock_pool_mdf A LEFT JOIN busday_pair B
	ON A.date = B.date
	ORDEr BY A.date;
QUIT;
DATA pef_stock(rename = (pre_date = date));
	SET pef_stock(drop = date rename = (stock_code = securityID));
	FORMAT pre_date yymmdd10.;
	FUND = "link1";
	IF "31jan2008"d <= pre_date <= "19aug2014"d;
RUN;
DATA pef_stock;
	SET pef_stock;
	year = year(date);
	month = month(date);
RUN;


PROC SQL;
	CREATE TABLE tmp AS
	SELECT year, month, max(date) FORMAT mmddyy10. AS date
	FROM pef_stock
	GROUP BY year, month;
QUIT;


PROC SQL;
	CREATE TABLE pef_stock_2 AS
	SELECT A.date, A.fund, A.weight, A.securityid, B.date AS date_b
	FROM pef_stock A LEFT JOIN tmp B
	ON  A.date = B.date
	ORDER BY A.date, A.weight desc;
QUIT;
DATA pef_stock(drop = date_b);
	SET pef_stock_2;
	IF date = date_b;
RUN;


PROc SORT DATA = pef_stock;
	BY date;
RUN;


%LET output_dir = D:\Research\DATA\yjyg_link\portfolio_data\500_por;
%LET filename = ;

%MACRO loop_output(stock_pool,fundname);
PROC SQL NOPRINT;
		CREATE TABLE tt AS
		SELECT distinct  date 
		FROM &stock_pool.

		ORDER BY date;

		SELECT date, count(*) 
		INTO :date_list separated by ' ',
			 :date_number
		FROM tt;

		 %DO date_index = 1 %TO &date_number.;
			%LET curdate = %scan(&date_list, &date_index., ' ');
			PROC SQL;
				CREATE TABLE exfile AS
				SELECT *
				FROM &stock_pool.
				WHERE date = input("&curdate.",yymmdd10.);
			QUIT;

			LIBNAME myxls  "&output_dir.\&fundname._&curdate..xls";
			DATa myxls.data;
				SET exfile;
			RUN;
			LIbNAME myxls clear;
		%END;
%MEND;

%loop_output(stock_pool=pef_stock,fundname = link1);


/** 基准，往前一天*/
PROC SQL;
	CREATE TABLE index_pool_data AS
	SELECT A.date, A.stock_code,A.weight, B.pre_date
	FROM index_component A LEFT JOIN busday_pair B
	ON A.date = B.date
	WHERE index_code = "000905"
	ORDEr BY A.date;
QUIT;
DATA index_pool_data(rename = (pre_date = date));
	SET index_pool_data(drop = date rename = (stock_code = securityID));
	FORMAT pre_date yymmdd10.;
	FUND = "zz500";
	IF "31jan2008"d <= pre_date <= "19aug2014"d;
RUN;
DATA index_pool_data;
	SET index_pool_data;
	year = year(date);
	month = month(date);
RUN;


PROC SQL;
	CREATE TABLE tmp AS
	SELECT year, month, max(date) FORMAT mmddyy10. AS date
	FROM index_pool_data
	GROUP BY year, month;
QUIT;


PROC SQL;
	CREATE TABLE index_pool_data_2 AS
	SELECT A.date, A.fund, A.weight, A.securityid, B.date AS date_b
	FROM index_pool_data A LEFT JOIN tmp B
	ON  A.date = B.date
	ORDER BY A.date, A.weight desc;
QUIT;
DATA index_pool_data(drop = date_b);
	SET index_pool_data_2;
	IF date = date_b;
RUN;


PROc SORT DATA = index_pool_data;
	BY date;
RUN;

%loop_output(stock_pool=index_pool_data,fundname = zz500);
