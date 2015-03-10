/** 目前正在运作的组合 */
**** 连接Gogoal数据库;
libname gogoal oracle user=fgtest password=fgtest4321 path='fgquant' schema=gogoal;

**** 连接天软数据库;
libname tinysoft oracle user=fgtest password=fgtest4321 path='fgquant' schema=tinysoftdb;

**** 连接行情数据库;
                libname hq oracle user=fgtest password=fgtest4321 path='fgquant' schema=hq;

**** 连接万得本地数据库;
            libname locwind oracle user=fgtest password=fgtest4321 path='fgquant' schema=fgwind;

OPTIONS MPRINT;   /* nomprint */
OPTIONS SYMBOLGEN;  /* nosymbolgen */

%LET my_dir = D:\Research\DATA\yjyg_link;
LIBNAME yl "&my_dir.\sasdata";

DATA run_stock_pool;
    ATTRIB
      stock_code LENGTH = $ 16
      stock_name LENGTH = $ 200
      efctid LENGTH = 8
      report_date LENGTH = 8 FORMAT = datetime20.
      report_period LENGTH = $ 16
      end_date LENGTH =  8 FORMAT = mmddyy10.
      ;
	 STOP;
RUN;

	
%MACRO construct_portfolio();
        %INCLUDE  "&my_dir.\code\run_daily_subset.sas";
        DATA cur_stock_pool;
                LENGTH
                        stock_code $ 16
                        stock_name $ 200
                        efctid  8
                        report_date 8
                        report_period $ 16
                        end_date 8
                ;
                FORMAT end_date mmddyy10.;
                FORMAT report_date  datetime20.;
                SET stock_pool;
                end_date =  &cur_date.;
        RUN;
%MEND construct_portfolio;


/** 假设每月底运行一次 **/
/** 取月底组合作为下一个月的组合 */

DATA tmp;
	SET busday;
	IF "31dec2007"d <= date <= "20aug2014"d;
	year = year(date);
	month = month(date);
RUN;

PROC SQL;
	CREATE TABLE busday_tmp2 AS
	SELECT year, month, max(date) FORMAT mmddyy10. AS date
	FROM tmp
	GROUP BY year, month;
QUIT;

%MACRO back_test();
        %LET benchmark_code = 000300;
        %LET start_date = '31dec2012'd;
       
		PROC SQL NOPRINT;
			CREATE TABLE tt AS
			SELECT distinct  date 
			FROM busday_tmp2
			ORDER BY date;

			SELECT date, count(*) 
			INTO :date_list separated by ' ',
			 	:date_number
			FROM tt;
		QUIT;

		%DO date_index = 1 %TO &date_number.;
			%LET cur_date = %scan(&date_list, &date_index., ' ');
			%LET cur_date = %SYSFUNC(inputn(&cur_date.,mmddyy10.));
			%LET date_min = &cur_date. - 150;
             %LET date_max = &cur_date. ;
			%LET start_date = '31dec2006'd; 
			%construct_portfolio();
			DATA run_stock_pool;
				SET run_stock_pool cur_stock_pool;
			RUN;
		%END;
			
%MEND back_test;

 %back_test();

 /** 扣除掉相隔超过60个交易日的股票 */
 %map_date_to_index(busday_table=busday, raw_table=run_stock_pool, date_col_name=end_date, raw_table_edit=link_stock_pool);
 DATA link_stock_pool;
 	SET link_stock_pool(rename = (date_index = end_date_index));
	report_date = datepart(report_date);
	FORMAT report_date mmddyy10.;
RUN;
%adjust_date(busday_table = busday, raw_table = link_stock_pool ,colname = report_date );
 %map_date_to_index(busday_table=busday, raw_table=link_stock_pool, date_col_name=adj_report_date, raw_table_edit=link_stock_pool);


 DATA link_stock_pool;
 	SET link_stock_pool;
	IF end_date_index-date_index>=60 THEN delete;
RUN;

/** 往后挪动一天变成下一个月，月初 */
PROC SQL;
	CREATE TABLE tmp AS
	SELECT stock_code, B.date, year(B.date) AS year, month(B.date) AS month
	FROM link_stock_pool A LEFT JOIN busday_pair B
	ON A.end_date = B.pre_date
	ORDER BY A.end_date;
QUIT;

/** 去除2014/8/21的组合，不再调整 */
DATA tmp;
	SET tmp;
	IF date = "21aug2014"d THEN delete;
RUN;



/** 生成每日组合 **/
DATA sub_busday;
	SET busday;
	IF  "01feb2008"d <= date <= "20aug2014"d;
	year = year(date);
	month = month(date);
RUN;
PROC SQL;
	CREATE TABLE tmp2 AS
	SELECT A.date, B.stock_code, 1 AS weight, 0 AS is_bm
	FROM sub_busday A LEFT JOIN tmp B
	ON A.year = B.year AND A.month = B.month
	ORDER BY A.date, B.stock_code;
QUIT;


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
	CREATE TABLE link_stock_pool AS
	SELECT A.*,B.adj_date, C.stock_code AS stock_code_c
	FROM tmp2 A LEFT JOIN adj_busdate B
	ON A.date = B.date
	LEFT JOIN  tinysoft.fg_uni_hs300 C
	ON A.stock_code = C.stock_code AND datepart(C.end_date) = B.adj_date
	ORDER BY A.stock_code, A.date;
QUIT;

DATA test_stock_pool(keep = date stock_code is_bm weight);
	SET link_stock_pool;
	IF stock_code_c = stock_code;
RUN;

%fill_in_index(my_library=work, stock_pool=test_stock_pool, busday_table=busday, start_date="01jan2007"d, 
		all_max_weight=1, ind_max_weight=0.05, edit_stock_pool=test_stock_pool_mdf);

/*%adjust_to_sector_neutral(my_library=work, stock_pool=test_stock_pool, start_date="01jan2007"d,*/
/*	max_within_indus=0.2, edit_stock_pool=test_stock_pool_mdf);*/

%fill_stock(my_library=work, stock_pool=test_stock_pool_mdf, edit_stock_pool=test_stock_pool_mdf);

DATA test_stock_pool_mdf;
	SET test_stock_pool_mdf;
	IF "01feb2008"d <= date <= "20aug2014"d;
RUN;

%cal_weighted_return(stock_pool=test_stock_pool_mdf);
%eval_pfmance();

%LET output_dir = D:\Research\DATA\yjyg_link\output_date_20140827;
%LET filename = run_60_pool_300.xls;

LIBNAME myxls  "&output_dir.\&filename.";
	DATa myxls.link_day;
		SET summary_day;
	RUN;

	DATA myxls.link_stat;
		SET summary_stat;
	RUN;
LIbNAME myxls clear;
