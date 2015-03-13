/** 代码功能：事件信号 --> 交易信号 */

/*** 输出:
(1) forecast_signal: 基于业绩预告的交易信号 
(2) actual_signal: 基于财报的交易信号
(3) merge_signal: 同时基于业绩预告/财报的交易信号 
数字字典可以参考"业绩事件提示表说明.txt"。
****/


%INCLUDE  "D:\Research\CODE\sascode\event\完整范例\date_macro.sas";
%LET tail_date = 28feb2015;


/* 外部表1: busdate */
PROC SQL;
	CREATE TABLE busday AS
	SELECT DISTINCT effective_date AS end_date
	FROM tinysoft.index_info
	ORDER BY effective_date;
QUIT;

DATA busday(drop = end_date);
	SET busday;
	date = datepart(end_date);
	FORMAT date mmddyy10.;
RUN;


/********* 模块1: 调整到交易日，同个日期的去重 ******/
/** 规则: 同个交易日，以报告期最大的为准 */

/* 利润表 */
%adjust_date(busday_table = busday , raw_table =earning_actual_merge,colname = report_date); 
DATA earning_actual_merge(drop = report_date_2 adj_report_date report_date_is_busday);
	SET earning_actual_merge(rename = (report_date = report_date_2));
	report_date = adj_report_date;
	FORMAT report_date mmddyy10.;
RUN;

PROC SORT DATA = earning_actual_merge;
	BY stock_code report_date descending report_period;
RUN;

PROC SORT DATA = earning_actual_merge NODUPKEY OUT = earning_actual_clear;
	BY stock_code report_date;
RUN;

/* 业绩预告 */
%adjust_date(busday_table = busday , raw_table =earning_forecast_merge,colname = report_date); 
DATA earning_forecast_merge(drop = report_date_2 adj_report_date report_date_is_busday);
	SET earning_forecast_merge(rename = (report_date = report_date_2));
	report_date = adj_report_date;
	FORMAT report_date mmddyy10.;
RUN;

PROC SORT DATA = earning_forecast_merge;
	BY stock_code report_date descending report_period descending source;
RUN;
PROC SORT DATA = earning_forecast_merge NODUPKEY OUT = earning_forecast_clear;
	BY stock_code report_date;
RUN;


/************ 模块2: 针对业绩预告和财报事件，分别构造买入/卖出信号 **/
DATA actual_signal(drop = is_improve);
	SET earning_actual_clear(keep = primary_key stock_code stock_name report_date report_period is_improve next_a_report_date next_f_report_date);
	IF report_date >= "&tail_date."d THEN delete;   /* 把最后一天新的记录剔除 */
	IF missing(next_a_report_date) OR next_a_report_date >= "&tail_date."d THEN next_a_report_date = "&tail_date."d;
	IF missing(next_f_report_date) OR next_f_report_date >= "&tail_date."d  THEN next_f_report_date = "&tail_date."d;
	IF is_improve IN (1) THEN a_signal = 1;   
	ELSE a_signal = 0;
RUN;


DATA forecast_signal(drop = eup_type is_improve);
	SET earning_forecast_clear(keep = primary_key eup_type stock_code stock_name report_date report_period is_improve next_a_report_date next_f_report_date);
	IF report_date >= "&tail_date."d THEN delete;   /* 把最后一天新的记录剔除 */
	IF missing(next_a_report_date) OR next_a_report_date >= "&tail_date."d THEN next_a_report_date = "&tail_date."d;
	IF missing(next_f_report_date) OR next_f_report_date >= "&tail_date."d  THEN next_f_report_date = "&tail_date."d;
	IF is_improve IN (1,0) AND strip(eup_type) IN ("预增")THEN f_signal = 1;
	ELSE f_signal = 0;
RUN;


/************ 模块3: 混合业绩预告和财报事件，分别构造买入/卖出信号 **/

PROC SQL;
	CREATE TABLE merge_signal AS
	SELECT A.primary_key AS f_key, A.stock_code AS f_stock_code, A.stock_name AS f_stock_name, A.report_date AS f_report_date,
			A.report_period AS f_report_period, A.f_signal, min(a.next_a_report_date,a.next_f_report_date) AS f_sell_date FORMAT mmddyy10.,
			B.primary_key AS a_key, B.stock_code AS a_stock_code, B.stock_name AS a_stock_name, B.report_date AS a_report_date,
			B.report_period AS a_report_period, B.a_signal, min(b.next_a_report_date,b.next_f_report_date) AS a_sell_date FORMAT mmddyy10.
	FROM forecast_signal A FULL JOIN actual_signal B
	ON A.stock_code = B.stock_code AND A.report_date = B.report_date
	ORDER BY A.stock_code, B.stock_code, A.report_date, B.report_date;
QUIT;

DATA merge_signal(keep = primary_key stock_code stock_name report_date report_period signal target sell_date);
	SET merge_signal;
	primary_key = _N_;
	report_date = max(a_report_date,f_report_date);  /** 缺失认为是最小值 */
	/* 如果财报和业绩预告在同个事件发布，以报告期最大的作为标准。如果报告期相同，则以财报作为标准*/
	IF not missing(f_key) AND not missing(a_key) THEN DO;
		stock_code = a_stock_code;
		stock_name = a_stock_name;
		IF f_report_period <= a_report_period THEN DO;
			signal = a_signal; 
			target = 0;
			report_period = a_report_period;
			sell_date = a_sell_date;
		END;
		ELSE DO;
			signal = f_signal;
			target = 1;
			report_period = f_report_period;
			sell_date = f_sell_date;
		END;
	END;
	ELSE IF missing(f_key) THEN DO;
		stock_code = a_stock_code;
		stock_name = a_stock_name;
		signal = a_signal; 
		target = 0;
		report_period = a_report_period;
		sell_date = a_sell_date;
	END;
	ELSE DO;
		stock_code = f_stock_code;
		stock_name = f_stock_name;
		signal = f_signal;
		target = 1;
		report_period = f_report_period;
		sell_date = f_sell_date;
	END;
	FORMAT report_date sell_date mmddyy10.;
RUN;
PROC SQL;
	DROP TABLE earning_actual_clear, earning_forecast_clear;
QUIT;



