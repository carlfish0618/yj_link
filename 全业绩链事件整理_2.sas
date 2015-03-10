/* 辅助表 */

%INCLUDE  "D:\Research\CODE\sascode\event\完整范例\date_macro.sas";

/* 所有A股 */
/*PROC SQL;*/
/*	CREATE TABLE a_stock_list AS*/
/*	SELECT distinct stock_code*/
/*	FROM hq.hqinfo*/
/*	WHERE type = "A"*/
/*	ORDER BY stock_code;*/
/*QUIT;*/

/* 排除未上市股票 */
/*PROC SQL;*/
/*	CREATE TABLE stock_info_table AS*/
/*	SELECT F16_1090 AS stock_code, OB_OBJECT_NAME_1090 AS stock_name,  F17_1090, F18_1090, F19_1090 AS is_delist, F6_1090 AS bk*/
/*	FROM locwind.tb_object_1090*/
/*	WHERE F4_1090 = 'A';*/
/**/
/*	CREATE TABLE not_list_stock AS*/
/*	SELECT distinct stock_code*/
/*	FROM stock_info_table*/
/*	WHERE missing(F17_1090) AND missing(F18_1090);*/
/*QUIT;*/
/**/
/*DATA stock_info_table(drop = F17_1090 F18_1090);*/
/*	SET stock_info_table;*/
/*	list_date = input(F17_1090,yymmdd8.);*/
/*	delist_date = input(F18_1090,yymmdd8.);*/
/*	IF index(stock_name,'ST') THEN is_st = 1;*/
/*	ELSE is_st = 0;*/
/*	FORMAT list_date delist_date mmddyy10.;*/
/*RUN;*/
/**/
/*PROC SQL;*/
/*	CREATE TABLE tmp AS*/
/*	SELECT **/
/*	FROM a_stock_list*/
/*	WHERE stock_code NOT IN*/
/*	(SELECT stock_code FROM not_list_stock);*/
/*QUIT;*/
/*DATA a_stock_list;*/
/*	SET tmp;*/
/*RUN;*/
/*PROC SQL;*/
/*	DROP TABLE tmp, not_list_stock;*/
/*QUIT;*/


/* 交易日 */
/*PROC SQL;*/
/*	CREATE TABLE busday AS*/
/*	SELECT DISTINCT effective_date AS end_date*/
/*	FROM tinysoft.index_info*/
/*	ORDER BY end_date;*/
/*QUIT;*/
/**/
/*DATA busday(drop = end_date);*/
/*	SET busday;*/
/*	IF not missing(end_date);*/
/*	date = datepart(end_date);*/
/*	FORMAT date mmddyy10.;*/
/*RUN;*/


/******* 模块1:  利润表*/
/* Step1: 当期数据 */
PROC SQL;
	CREATE TABLE earning_actual  AS
	SELECT f16_1090 AS stock_code ,ob_object_name_1090 AS stock_name,f2_1854 AS report_period,f3_1854 AS report_date_2, 
		f61_1854 AS earning_n
	FROM locwind.tb_object_1854 AS a LEFT JOIN locwind.TB_OBJECT_1090 AS b 
	ON a.F1_1854 = b.OB_REVISIONS_1090  
  	WHERE b.f4_1090='A' AND a.f4_1854='合并报表' AND input(A.F3_1854,8.) >= 20040000 AND B.F16_1090 IN     /** 从2006年开始进行策略回溯 */
	(SELECT stock_code FROM a_stock_list);

	CREATE TABLE earning_actual_raw AS
	SELECT a.*, b.report_period AS report_period_o, b.earning_n AS earning_o, 
		round((a.earning_n - b.earning_n)/abs(b.earning_n)*100, 0.01) AS gro_n
	FROM earning_actual AS a LEFT JOIN earning_actual AS b
	ON input(a.report_period,8.) - 10000 = input(b.report_period,8.) AND a.stock_code = b.stock_code
	ORDER BY a.stock_code, a.report_period;
QUIT;

/* Step2: 同比数据 */
DATA earning_actual_raw(drop = report_date_2);
	SET earning_actual_raw;
	report_date = input(trim(left(report_date_2)),yymmdd8.);
	report_period = trim(left(report_period));
	format report_date mmddyy10.;
	/*盈利分类：1为持续亏损、2为扭亏、3为首亏、4为持续正盈利 */
	IF NOT MISSING (earning_o) AND NOT missing(earning_n) THEN DO;
		IF earning_o<=0 and earning_n<=0 THEN DO;
			e_type=1;
/*			gro_n = .;   增速无效 */
		END; 
   		ELSE IF earning_o<=0 and earning_n>0 THEN DO;
			e_type=2;
/*			gro_n = .;*/
		END;
   		ELSE IF  earning_o>0 and earning_n<=0 THEN DO;
			e_type=3;
/*			gro_n = .;  增速无效 */
		END;
    	ELSE IF  earning_o>0 and earning_n>0 THEN e_type=4;
	END;
	ELSE e_type = .;
RUN;

/* Step3: (已发布的)最近季度的利润数据: */
PROC SQL;
	CREATE TABLE tmp AS
	SELECT A.*, B.report_period AS prev_report_period, B.report_date AS prev_report_date, B.gro_n AS prev_gro_n,
		B.e_type AS prev_e_type
	FROM earning_actual_raw A LEFT JOIN earning_actual_raw B
	ON a.report_period > b.report_period AND A.stock_code = B.stock_code AND a.report_date >= b.report_date 
	ORDER BY A.stock_code, A.report_period, A.report_date, B.report_period desc, B.report_date desc;
QUIT;

DATA earning_actual_merge;
	SET tmp;
	BY stock_code report_period report_date;
	IF first.report_date;
RUN;



/* Step4: 相邻季度，增速的环比数据*/
PROC SQL;
	CREATE TABLE tmp AS
	SELECT A.*, B.report_period AS nb_report_period, B.report_date AS nb_report_date, B.gro_n AS nb_gro_n,B.e_type AS nb_e_type
	FROM earning_actual_merge A LEFT JOIN earning_actual_merge B
	ON input(a.report_period,8.)-input(b.report_period,8.) IN (299,300,301,9100) AND A.stock_code = B.stock_code
	ORDER BY A.stock_code, A.report_period, A.report_date;
QUIT;

DATA earning_actual_merge;
	SET tmp;
	IF e_type = 4 AND nb_e_type = 4 THEN DO;
		IF gro_n >= nb_gro_n THEN nb_type = 1;
		ELSE IF gro_n < nb_gro_n THEN nb_type = 2;
	END;
	ELSE nb_type = .;
RUN;


/* 检验通过: 针对同一个公告期，不存在重复值*/
/*PROC SORT DATA = earning_actual_merge NODUPKEY;*/
/*	BY stock_code report_period;*/
/*RUN;*/

/* 暂时不去重 */
/* 存在重复观测值，因为季报和年报可能同时公告。保留最新公告期的数据 */

PROC SORT DATA = earning_actual_merge;
	BY stock_code report_date descending report_period;
RUN;

/*PROC SORT DATA = earning_actual_merge NODUPKEY;*/
/*	BY stock_code report_date;*/
/*RUN;  */



	
/********* 模块2: 业绩预告表数据 */
/* Step1: 当期业绩预告 */
PROC SQL;
	CREATE TABLE earning_forecast_raw AS
	SELECT b.symbol AS stock_code label "stock_code",b.sname AS stock_name label "stock_name",a.*
	FROM gogoal.efct AS a LEFT JOIN gogoal.securitycode AS b 
	ON  a.companycode = b.companycode
   	WHERE (b.exchange='CNSESH' or b.exchange='CNSESZ') AND datepart(reportdate)>= "01jan2005"d
	AND B.symbol IN (SELECT stock_code FROM a_stock_list);
QUIT;

DATA earning_forecast_raw(keep=stock_code stock_name efctid  report_date report_period 
				reportunit source earning_des eup_num eup_ratio eup_type elow_num elow_ratio elow_type report_period_o);
	SET earning_forecast_raw;
	RENAME reportdate = report_date efct14 = source efct11 = earning_des
			efct9 = eup_num efct10 = eup_ratio efct12 = eup_type 
			efct15 = elow_num efct16 = elow_ratio efct17 = elow_type;
	period_type = substr(forecastsession,5,1);
	IF (substr(stock_code,1,1) = "0" OR substr(stock_code,1,1) = "6")  /* A股 */
	AND substr(stock_code,1,2) ~= "03" AND  stock_name ~= "上药转换"    /*剔除权证和上药转换*/
	AND period_type="3" or period_type="1" or period_type="4" or period_type="2"  /*数据处理：剔除单季度预测和定性描述*/
	AND not missing(efct11)
	AND (not missing(efct9) OR not missing(efct10) OR not missing(efct15) OR not missing(efct16)); /* 至少需要上下限增长率或绝对值有一个存在)*/
	period_year = input(substr(forecastsession,1,4),8.);
	period_year_o = input(substr(forecastsession,1,4),8.)-1;
	IF  input(substr(forecastsession,1,5),8.)- input(substr(forecastbasesession,1,5),8.)=10;  /* 只保留同比数据 */
	IF period_type='3' THEN DO;
        report_period=trim(left(period_year||"0331"));
		report_period_o=trim(left(period_year_o||"0331"));	
   	END;
   	ELSE IF period_type='1' THEN DO;
       	report_period=trim(left(period_year||"0630"));	
		report_period_o=trim(left(period_year_o||"0630"));	
	END;
	ELSe IF period_type='4' THEN DO;
       	report_period=trim(left(period_year||"0930"));	
		report_period_o=trim(left(period_year_o||"0930"));		
	END;
	ELSE IF period_type='2' THEN DO;
       	report_period=trim(left(period_year||"1231"));
		report_period_o=trim(left(period_year_o||"1231"));		
	END;	
RUN;

/* 匹配业绩预告中基期的真实业绩增长率，以计算更为准确的增长上下限 */
PROC SQL;
	CREATE TABLE tmp AS
	SELECT A.*,b.earning_n 
	FROM earning_forecast_raw a LEFT JOIN earning_actual_raw b
	ON trim(left(a.stock_code)) = trim(left(b.stock_code)) AND a.report_period_o = b.report_period;
QUIT;

DATA  earning_forecast_raw(rename = (earning_n = base_earning_n)) ;  /* 保留基期的净利润 */
	SET tmp;
	report_date = datepart(report_date);
	FORMAT report_date mmddyy10.;
	*单位转换;
    IF reportunit='百万' THEN DO; 
		eup_num=eup_num*1000000;
		elow_num=elow_num*1000000;	
    END; 
	ELSE IF reportunit='千元' THEN DO;
    		eup_num=eup_num*1000;
			elow_num=elow_num*1000;				
    END; 
	ELSE IF reportunit='万元' THEN DO;
    		eup_num=eup_num*10000;
			elow_num=elow_num*10000;				
    END;
    ELSE IF reportunit='元' THEN DO;
    		eup_num=eup_num*1;
			elow_num=elow_num*1;				
    END;    
	ELSE IF reportunit='亿' or reportunit='亿元' THEN DO;
    		eup_num=eup_num*10000000;
			elow_num=elow_num*100000000;				
    END; 
    
    /*计算增长率(只针对所有正收益率）*/;
	IF earning_n>0 and eup_num>0 THEN eup_ratio_c = round((eup_num-earning_n)/abs(earning_n)*100,0.01);		
	IF earning_n>0 and elow_num>0 THEN elow_ratio_c = round((elow_num-earning_n)/abs(earning_n)*100,0.01); 		
  	
	is_up_original = 1;
	is_low_original = 1;

	

	/*定义最后的增长率-上限(是否依赖计算所得）*/;
    IF NOT MISSING(eup_ratio) AND eup_ratio~= 0 THEN eup_ratio_f=eup_ratio;
/*    IF NOT MISSING(eup_ratio) THEN eup_ratio_f=eup_ratio;*/
    ELSE DO;
   	  eup_ratio_f=eup_ratio_c;	
	  is_up_original = 0;
    END;
   /*    IF eup_ratio =0 and eup_num>0 THEN DO;
   	  eup_ratio_f=eup_ratio_c;	
	  is_up_original = 0;
    END; */

   /*定义最后的增长率-下限*/
   IF NOT MISSING(elow_ratio) AND elow_ratio ~= 0 THEN elow_ratio_f=elow_ratio; 
/* IF NOT MISSING(elow_ratio)  THEN elow_ratio_f=elow_ratio; */
   ELSE DO;
   	  elow_ratio_f=elow_ratio_c;	
	  is_low_original = 0;
   END;
   /* 如果可以比较，则调换顺序 */
   IF not missing(eup_ratio_f) AND not missing(elow_ratio_f) THEN DO;
   		eup = max(eup_ratio_f, elow_ratio_f);
		elow = min(eup_ratio_f, elow_ratio_f);
		IF eup_ratio_f < elow_ratio_f THEN DO;  /* 如果有调换，重新调整下mark*/
			tmp = is_low_original;
			is_up_original = tmp;
			is_low_original = is_up_original;
		END;
   END;
   ELSE DO;
   		eup = eup_ratio_f;
		elow=elow_ratio_f;
   END;

   /** 根据含义，填补可能缺失的上下线 */
/*	IF missing(eup) THEN DO;*/
/*		IF eup_type IN ("预盈") THEN eup = 50;*/
/*		IF eup_type IN ("预降") THEN eup = 0;*/
/*		IF eup_type IN ("预减") THEN eup = -50;*/
/*	END;*/
/*	IF missing(elow) THEN DO;*/
/*		IF eup_type IN ("预增") THEN elow = 50;*/
/*		IF eup_type IN ("预降") THEN elow = -50;*/
/*		IF eup_type IN ("预盈") THEN elow = 0;*/
/*	END;*/

   /*定义不同预测类型：0为基期利润小于0，1为基期利润大于0但上限和下限无意义，2为基期利润大于0，上下限有一个缺失，3为基期利润大于0，上下限都无缺失 */
   IF earning_n <= 0 THEN f_type = 0;
   ELSE IF missing(eup) AND missing(elow) THEN f_type = 1;
   ELSE IF missing(eup) OR missing(elow) THEN f_type = 2;
   ELSE f_type = 3;
  
  /* 保留需要的字段 */
   KEEP efctid stock_code stock_name report_date report_period source earning_des
      eup_type eup elow_type elow f_type is_up_original is_low_original report_period_o earning_n;
RUN;

/* Step2: （已发布的）最近季度的真实业绩公告期*/
/* 特例：若现在公布半年报数据，而历史已公布数据中：A去年年报滞后于当年一季度报，则仍选取一季报结果*/

PROC SQL;
	CREATE TABLE tmp AS
	SELECT A.*, B.report_period AS a_report_period, B.report_date AS a_report_date,
			B.gro_n AS a_gro_n, B.e_type AS a_e_type, B.earning_n AS a_earning_n
	FROM earning_forecast_raw A LEFT JOIN earning_actual_merge B
	ON A.stock_code = B.stock_code AND A.report_period > B.report_period AND A.report_date>= B.report_date 
	ORDER BY A.efctid, B.report_period desc, B.report_date desc;
QUIT;

/* 选取最近发布的真实业绩公告结果*/
DATA earning_forecast_merge;
	SET tmp;
	BY efctid;
	IF first.efctid; 
RUN;

/** Step2-appendix: 补充，（未发布）同一季度的真实业绩公告期*/
/** 目的：为了统计一下二者的时间差 **/
/*PROC SQL;*/
/*	CREATE TABLE tmp AS*/
/*	SELECT A.*, B.report_period AS same_report_period, B.report_date AS same_report_date,*/
/*			B.gro_n AS same_gro_n, B.e_type AS same_e_type, B.earning_n AS same_earning_n*/
/*	FROM earning_forecast_raw A LEFT JOIN earning_actual_merge B*/
/*	ON A.stock_code = B.stock_code AND A.report_period = B.report_period */
/*	ORDER BY A.efctid, B.report_date; */
/*QUIT;*/

/* 选取最近发布的真实业绩公告结果*/
/*DATA earning_forecast_merge;*/
/*	SET tmp;*/
/*	BY efctid;*/
/*	IF first.efctid;*/
/*RUN;*/


/* Step 3: （之前）最近一期的业绩预告/
/* 特例：若现在公布半年报数据，而历史已公布数据中：A的去年年报预告滞后于当年一季度报预告，则仍选取一季报预告结果*/
/* 最近一期业绩预告有多条公布记录，优先序：公布时间>临时公告>3季度报>半年报>1季度报 */

PROC SQL;
	CREATE TABLE tmp AS
	SELECT A.*, B.efctid AS prev_efctid, B.report_date AS prev_report_date, B.report_period AS prev_report_period,
		B.source AS prev_source, B.earning_des AS prev_earning_des,
		B.eup_type AS prev_eup_type, B.eup AS prev_eup, B.elow_type AS prev_elow_type, B.elow AS prev_elow,
		 B.f_type AS prev_f_type, 
		B.is_up_original AS prev_is_up_original, B.is_low_original AS prev_is_low_original
	FROM earning_forecast_merge A LEFT JOIN earning_forecast_raw B
	ON A.stock_code = B.stock_code AND A.report_period > B.report_period AND A.report_date >= B.report_date
	ORDER BY A.efctid, B.report_period desc, B.report_date desc, B.source desc;
QUIT;
DATA earning_forecast_merge;
	SET tmp;
	BY efctid;
	IF first.efctid;
RUN;


/* Step 4: 完善基础信号: choose + is_valid + is_qoq */
/* 基础信号共3个（信号值不缺失）：*/
/* choose: 1-以真实公告为比较基准，0-以前期业绩预告为比较基准；当之前没有任何比较基准允许缺失，*/
/* is_valid: 1-比较基准有意义，0-比较基准无意义 */
/* is_qoq: 1- 恰好是季度环比，0- 不是相邻季度的环比 */

DATA earning_forecast_merge;
	SET earning_forecast_merge;

	/* 建立业绩链比较基准： 1-（本期或前期）真实业绩公告， 0-前期业绩预告*/
	IF NOT MISSING(prev_report_period) AND NOT MISSING(a_report_period) THEN DO;
		IF input(prev_report_period,8.) <= input(a_report_period,8.) THEN choose = 1; 
		ELSE choose = 0; 
	END;
	ELSE IF NOT MISSING(prev_report_period) THEN choose = 0;
	ELSE IF NOT MISSING(a_report_period) THEN choose = 1;
	ELSE choose = .;
	
	IF choose = 1 THEN cmp_period = a_report_period;
	ELSE IF choose = 0 THEN cmp_period = prev_report_period;
	ELSE cmp_period = .;

	/* 相隔时间超过1年，比较基准失效*/
	IF NOT MISSING(cmp_period) THEN DO;
		IF input(report_period,8.)-input(cmp_period,8.)>10000 THEN
			is_valid = 0;
    	ELSE is_valid = 1;
	END;
	ELSE is_valid = 0;
	
	IF NOT missing(cmp_period) THEN DO;
		IF input(report_period,8.)-input(cmp_period,8.) IN (301,300,299,9100) AND is_valid = 1 THEN is_qoq = 1;
		ELSE is_qoq = 0;
	END;
	ELSE is_qoq = 0;
	
RUN; 

/* Step 5: 构造间接信号：依据条件允许信号值缺失 */
DATA earning_forecast_merge(drop = d_eup d_elow);
	SET earning_forecast_merge;
	d_eup = eup - a_gro_n;
	d_elow = elow - a_gro_n;

	/* 1- is_link: 业绩链是否有意义(至少有一个上下限，同时存在一年内的基期比较） */
	IF f_type >=2  AND is_valid = 1 THEN is_link = 1;
	ELSE is_link = 0;

	/* 2- is_signal: 改善与否信号是否有意义（前提：is_link = 1)*/
	/* 注意：只有在 a_e_type = 4 的情况下，a_gro_n 的计算才是准确的 */
	/*       只有在 prev_f_type >=2 的情况下，prev_eup 和 prev_elow 才有意义  */
	IF is_link = 1 THEN DO;
		IF (choose = 1 AND a_e_type = 4) OR (choose = 0 AND prev_f_type >=2) THEN is_signal = 1;
		ELSE is_signal = 0;
	END;
	ELSE is_signal = .;

	/* 3- is_improve: 创建改善与否信号（前提：is_signal = 1) */
	/* 1- 绝对改善，0-不确定，-1-绝对恶化，2-数据本身不确定性强*/
	IF is_signal = 1 THEN DO;
		IF choose = 1 THEN DO; /*真实业绩*/
			IF not missing(eup) AND not missing(elow) THEN DO;
				IF d_elow > 0 THEN is_improve = 1;
				ELSE IF d_elow <= 0 AND d_eup >= 0 THEN is_improve = 0;
				ELSE is_improve = -1;
			END;
			ELSE IF not missing(elow) THEN DO;
				IF d_elow > 0 THEN is_improve = 1;
				ELSE is_improve = 0;
			END;
			ELSE DO;
				IF d_eup < 0 THEN is_improve = -1;
				ELSE is_improve = -1;  /* 这里修改为-1，因为不确定性太强 */
			END;
		END;
		ELSE DO; /*前期预告*/
			IF NOT MISSING(eup) AND NOT MISSING(elow) AND NOT MISSING(prev_eup) AND NOT MISSING(prev_elow) THEN DO;
/*				IF elow >= prev_eup THEN is_improve = 1;*/
/*				ELSE IF eup <= prev_elow THEN is_improve = -1;*/
/*				ELSE is_improve = 0;*/
				IF elow > prev_elow AND eup >= prev_eup THEN is_improve = 1;
				ELSE is_improve = -1;
			END;
			ELSE IF NOT MISSING(eup) AND NOT MISSING(elow) AND NOT MISSING(prev_eup) THEN DO; /* 前一期无下限*/
/*				IF elow >= prev_eup THEN is_improve = 1;*/
/*				ELSE is_improve = 0;*/
				IF eup >= prev_eup THEN is_improve = 1;
				ELSE is_improve = -1;
			END;
			ELSE IF NOT MISSING(eup) AND NOT MISSING(elow) AND NOT MISSING(prev_elow) THEN DO; /* 前一期无上限 */
/*				IF eup <= prev_elow THEN is_improve = -1;*/
/*				ELSE is_improve = 0;*/
				is_improve = -1;
			END;	
			ELSE IF NOT MISSING(elow) AND NOT MISSING(prev_eup) AND NOT MISSING(prev_elow) THEN DO; /* 当期无上限 */
/*				IF elow >= prev_eup THEN is_improve = 1;*/
/*				ELSE is_improve = 0;*/
				IF elow > prev_elow THEN is_improve = 1;
				ELSE is_improve = -1;
			END;
			ELSE IF NOT MISSING(eup) AND NOT MISSING(prev_eup) AND NOT MISSING(prev_elow) THEN DO;  /* 当期无下限 */
/*				IF eup <= prev_elow THEN is_improve = -1; */
/*				ELSE is_improve = 0;*/
				is_improve = -1;
			END;
			ELSE is_improve = 2; /* too many uncertainty */
		END;
	END;
	ELSE is_improve = .;
RUN;

/******* 模块3: 完善利润表（与当期的业绩预告结合）*/
PROC SQL;
	CREATE TABLE tmp AS
	SELECT A.*, B.efctid AS ff_efctid, B.report_date AS ff_report_date, B.source AS ff_source,
	B.earning_des AS ff_earning_des, B.eup AS ff_eup, B.eup_type AS ff_eup_type,
	B.elow AS ff_elow, B.elow_type AS ff_elow_type, B.f_type AS ff_f_type,
	B.is_up_original AS ff_is_up_original, B.is_low_original AS ff_is_low_original
	FROM earning_actual_merge A LEFT JOIN earning_forecast_raw B
	ON A.stock_code = B.stock_code AND A.report_period = B.report_period AND A.report_date>=B.report_date
	ORDER BY A.stock_code, A.report_period, B.report_date desc, B.source desc;
QUIT;



/** （已发布的) 最近季度的业绩预告数据 **/
PROC SQL;
	CREATE TABLE tmp AS
	SELECT A.*, B.efctid AS pf_efctid, B.report_date AS pf_report_date, B.report_period AS pf_report_period, B.source AS pf_source,
	B.earning_des AS pf_earning_des, B.eup AS pf_eup, B.eup_type AS pf_eup_type,
	B.elow AS pf_elow, B.elow_type AS pf_elow_type, B.f_type AS pf_f_type,
	B.is_up_original AS pf_is_up_original, B.is_low_original AS pf_is_low_original
	FROM earning_actual_merge A LEFT JOIN earning_forecast_raw B
	ON A.stock_code = B.stock_code AND A.report_period >= B.report_period AND A.report_date>=B.report_date
	ORDER BY A.stock_code, A.report_period, A.report_date, B.report_period desc, B.report_date desc, B.source desc;
QUIT;


DATA earning_actual_merge;
	SET tmp;
	BY stock_code report_period report_date;
	IF first.report_date;
	/* 建立业绩链比较基准： 1-最近真实业绩公告， 0-最近业绩预告*/
	IF NOT MISSING(prev_report_period) AND NOT MISSING(pf_report_period) THEN DO;
		IF input(pf_report_period,8.) <= input(prev_report_period,8.) THEN choose = 1; 
		ELSE choose = 0; 
	END;
	ELSE IF NOT MISSING(pf_report_period) THEN choose = 0;
	ELSE IF NOT MISSING(prev_report_period) THEN choose = 1;
	ELSE choose = .;
	
	IF choose = 1 THEN cmp_period = prev_report_period;
	ELSE IF choose = 0 THEN cmp_period = pf_report_period;
	ELSE cmp_period = .;

	/* 相隔时间超过1年，比较基准失效*/
	IF NOT MISSING(cmp_period) THEN DO;
		IF input(report_period,8.)-input(cmp_period,8.)>10000 THEN
			is_valid = 0;
    	ELSE is_valid = 1;
	END;
	ELSE is_valid = 0;
	
	IF choose = 1 THEN DO;
		IF input(report_period,8.)-input(cmp_period,8.) IN (301,300,299,9100) AND is_valid = 1 THEN is_qoq = 1;
		ELSE is_qoq = 0;
	END;
	ELSE IF choose = 0 THEN DO;
		IF report_period = cmp_period AND is_valid = 1 THEN is_qoq = 1;
		ELSE is_qoq = 0;
	END;
	ELSE is_qoq = 0;
	
RUN; 

/* Step 5: 构造间接信号：依据条件允许信号值缺失 */
DATA earning_actual_merge;
	SET earning_actual_merge;

	/* 1- is_link: 业绩链是否有意义(只考虑持续盈利的情况，这时候gro_n有意义） */
	IF e_type =4  AND is_valid = 1 THEN is_link = 1;
	ELSE is_link = 0;

	/* 2- is_signal: 改善与否信号是否有意义（前提：is_link = 1)*/
	/* 注意：只有在 prev_e_type = 4 的情况下，prev_gro_n 的计算才是准确的 */
	/*       只有在 pf_f_type >=2 的情况下，pf_eup 和 pf_elow 才有意义  */
	IF is_link = 1 THEN DO;
		IF (choose = 1 AND prev_e_type = 4) OR (choose = 0 AND pf_f_type >=2) THEN is_signal = 1;
		ELSE is_signal = 0;
	END;
	ELSE is_signal = .;

	/* 3- is_improve: 创建改善与否信号（前提：is_signal = 1) */
	/* 1- 绝对改善，0-不确定，-1-绝对恶化，2-数据本身不确定性强*/
	IF is_signal = 1 THEN DO;
		IF choose = 1 THEN DO; /*真实业绩*/
			IF	gro_n >= prev_gro_n THEN is_improve = 1;
			ELSE is_improve = -1;
		END;
		ELSE DO; /*前期预告*/
			IF NOT MISSING(pf_eup) AND NOT MISSING(pf_elow) THEN DO;
				IF gro_n > pf_elow THEN is_improve = 1;
				ELSE is_improve = -1;
			END;
			ELSE IF missing(pf_elow) THEN DO; /* 前一期无下限，只能以上线为比较标准*/
				IF gro_n >= pf_eup THEN is_improve = 1;
				ELSE is_improve = -1;
			END;
			ELSE IF missing(pf_eup) THEN DO; /* 前一期无上限 */
				IF gro_n > pf_elow THEN is_improve = 1;
				ELSE is_improve = -1;
			END;	
		END;
	END;
	ELSE is_improve = .;
RUN;


PROC SQL;
	DROP TABLE tmp, earning_forecast_raw, earning_actual_raw, earning_actual;
QUIT;



/********* 模块4: 调整到交易日，同个日期的去重 **/
DATA earning_actual_merge;
	SET earning_actual_merge;
	id = _N_;
RUN;
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


PROC SORT DATA = earning_actual_merge;
	BY stock_code report_date descending report_period;
RUN;

PROC SORT DATA = earning_actual_merge NODUPKEY OUT = earning_actual_clear;
	BY stock_code report_date;
RUN;

/* 业绩预告 */
%adjust_date(busday_table = busday , raw_table =earning_forecast_merge,colname = report_date); 
DATA earning_forecast_merge(drop = report_date_2 adj_report_date report_date_is_busday);
	SET earning_forecast_merge(rename = (report_date = report_date_2 efctid = id));
	report_date = adj_report_date;
	FORMAT report_date mmddyy10.;
RUN;

PROC SORT DATA = earning_forecast_merge;
	BY stock_code report_date descending report_period descending source;
RUN;
PROC SORT DATA = earning_forecast_merge NODUPKEY OUT = earning_forecast_clear;
	BY stock_code report_date;
RUN;


/*** 模块5: 构造买入/卖出信号 **/
DATA actual_signal;
	SET earning_actual_clear(keep = id stock_code stock_name report_date report_period is_improve);
	IF is_improve IN (1) THEN a_signal = 1;   
	ELSE a_signal = 0;
RUN;

DATA forecast_signal(drop = eup_type);
	SET earning_forecast_clear(keep = id eup_type stock_code stock_name report_date report_period is_improve);
	IF is_improve IN (1,0) AND strip(eup_type) IN ("预增")THEN f_signal = 1;
	ELSE f_signal = 0;
RUN;




PROC SQL;
	CREATE TABLE merge_signal AS
	SELECT A.id AS f_id, A.stock_code AS f_stock_code, A.stock_name AS f_stock_name, A.report_date AS f_report_date, A.report_period AS f_report_period, A.f_signal, 
		B.id AS a_id, B.stock_code AS a_stock_code,B.stock_name AS a_stock_name,  B.report_date AS a_report_date, B.report_period AS a_report_period, B.a_signal
	FROM forecast_signal A FULL JOIN actual_signal B
	ON A.stock_code = B.stock_code AND A.report_date = B.report_date
	ORDER BY A.stock_code, B.stock_code, A.report_date, B.report_date;
QUIT;

DATA merge_signal(keep = stock_code stock_name report_date report_period signal tar_cmp rename = (report_date = date));
	SET merge_signal;
	report_date = max(a_report_date,f_report_date);
	IF not missing(f_id) AND not missing(a_id) THEN DO;
		stock_code = a_stock_code;
		stock_name = a_stock_name;
		IF f_report_period <= a_report_period THEN DO;
			signal = a_signal; /* 如果财报和业绩预告在同个事件发布，且是针对同个报告期，则以财报数据为准 */
			tar_cmp = 0;
			report_period = a_report_period;
		END;
		ELSE DO;
			signal = f_signal;
			tar_cmp = 1;
			report_period = f_report_period;
		END;
	END;
	ELSE IF missing(f_id) THEN DO;
		stock_code = a_stock_code;
		stock_name = a_stock_name;
		signal = a_signal;
		tar_cmp = 0;
		report_period = a_report_period;
	END;
	ELSE DO;
		stock_code = f_stock_code;
		stock_name = f_stock_name;
		signal = f_signal;
		tar_cmp = 1;
		report_period = f_report_period;
	END;
	FORMAT report_date mmddyy10.;
RUN;
PROC SQL;
	DROP TABLE actual_signal, forecast_signal;
QUIT;


/*PROC SQL;*/
/*	CREATE TABLE tmp AS*/
/*	SELECT **/
/*	FROM merge_signal*/
/*	WHERE missing(stock_code) OR missing(report_date) OR missing(signal) OR missing(tar_cmp) OR missing(report_period);*/
/*QUIT;*/
/**/
/*PROC SQL;*/
/*	CREATE TABLE tmp AS*/
/*	SELECT tar_cmp, signal, count(1) AS nobs*/
/*	FROM merge_signal*/
/*	GROUP BY tar_cmp, signal;*/
/*QUIT;*/


