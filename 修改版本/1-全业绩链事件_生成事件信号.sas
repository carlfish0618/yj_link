/*** 代码功能: 对利润表和业绩预告表信息进行整理 */

/**** 最终输出:
(1) 利润表：earning_actual_merge
(2)　业绩预告表：earning_forecast_merge
数字字典可以参考"业绩事件提示表说明.txt"。
***/


%INCLUDE  "F:\Research\GIT_BACKUP\utils\date_macro.sas";

/** 新增：日期开始-结束标志 **/
%LET endDate = 2009-12-31;  /** 回测开始的日期 */
%LET myEndDate = 31dec2009;

DATA _NULL_;
	end_date = input("&endDate.", yymmdd10.);
	y = year(end_date) - 2;
	start_date = input("31Dec"||put(y,4.),date9.);  
	act_date = input("31Dec"||put(y-1,4.),date9.);  
	/**　业绩预告发布时间的最大和最小值　**/
	call symput("minDate", put(start_date, date9.));  
	call symput("maxDate","01Jan2100");  
	/** 财报发布时间的最大和最小值 **/
	call symput("actMinDate",put(act_date,yymmddn8.));
	call symput("actMaxDate","21000101");  
	call symput("actMinDate2",put(start_date,yymmddn8.));   
RUN;




/************************** 模块1:  利润表***********/
/*** primary key: (stock_code, report_period) */ 
/* 检验通过: 针对同一个公告期，不存在重复值*/
/*PROC SORT DATA = earning_actual_merge NODUPKEY;*/
/*	BY stock_code report_period;*/
/*RUN;*/

/* Step1: 当期数据 */
PROC SQL;
	CREATE TABLE earning_actual  AS
	SELECT trim(left(f16_1090)) AS stock_code LABEL "stock_code" ,
			ob_object_name_1090 AS stock_name LABEL "stock_name",
			trim(left(f2_1854)) AS report_period LABEL "report_period",
			input(trim(left(f3_1854)),yymmdd8.) AS report_date LABEL "report_date" FORMAT mmddyy10.,
			f61_1854 AS earning_n LABEL "earning_n"
	FROM locwind.tb_object_1854 AS a LEFT JOIN locwind.TB_OBJECT_1090 AS b 
	ON a.F1_1854 = b.OB_REVISIONS_1090  
  	WHERE b.f4_1090='A' AND a.f4_1854='合并报表' AND A.F2_1854 >= "&actMinDate"  AND A.F2_1854 <=  "&actMaxDate";

	CREATE TABLE earning_actual_raw AS
	SELECT a.*, b.report_period AS report_period_o LABEL "report_period_o",
			b.earning_n AS earning_o LABEL "earning_o", 
			round((a.earning_n - b.earning_n)/abs(b.earning_n)*100, 0.01) AS gro_n
	FROM earning_actual AS a LEFT JOIN earning_actual AS b
	ON input(a.report_period,8.) - 10000 = input(b.report_period,8.) AND a.stock_code = b.stock_code
	AND a.report_date >= b.report_date
	WHERE a.report_period >= "&actMinDate2"  /** 从取同比的第二年开始 */
	ORDER BY a.stock_code, a.report_period;
QUIT;

/* Step2: 同比数据 */
DATA earning_actual_raw;
	SET earning_actual_raw;
	primary_key = _N_;
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
/** 在T时点，并不会出现已经出现T+1时点的财报公告（所以a.report_period > b.report_period是否增加都可以)**/

PROC SQL;
	CREATE TABLE earning_actual_merge AS
	SELECT A.*, B.report_period AS prev_report_period LABEL "prev_report_period", 
		B.report_date AS prev_report_date LABEL "prev_report_date", 
		B.gro_n AS prev_gro_n LABEL "prev_gro_n",
		B.e_type AS prev_e_type LABEL "prev_e_type" 
	FROM earning_actual_raw A LEFT JOIN 
	(
	SELECT stock_code, report_period, report_date, gro_n, e_type   /** 选子集能让速度变快 */
	FROM earning_actual_raw
	)B
	ON a.report_period > b.report_period AND A.stock_code = B.stock_code AND a.report_date >= b.report_date 
	GROUP BY A.primary_key
	HAVING max(B.report_period) = B.report_period 
	ORDER BY primary_key;
QUIT;


/****** 以下这个没有必要（因为很可能和“最近季度的利润数据”重合) ***/
/* Step4: 相邻季度，增速的环比数据*/
/*PROC SQL;*/
/*	CREATE TABLE tmp AS*/
/*	SELECT A.*, B.report_period AS nb_report_period LABEL "nb_report_period", */
/*	B.report_date AS nb_report_date LABEL "nb_report_date", */
/*	B.gro_n AS nb_gro_n LABEL "nb_gro_n",*/
/*	B.e_type AS nb_e_type LABEL "nb_e_type"*/
/*	FROM earning_actual_merge A LEFT JOIN earning_actual_merge B*/
/*	ON input(a.report_period,8.)-input(b.report_period,8.) IN (299,300,301,9100) AND A.stock_code = B.stock_code*/
/*	AND A.report_date >= B.report_date*/
/*	GROUP BY A.primary_key*/
/*	HAVING max(B.report_date) = B.report_date*/
/*	ORDER BY A.primary_key;*/
/*QUIT;*/

DATA earning_actual_merge;
	SET earning_actual_merge;
	IF e_type = 4 AND prev_e_type = 4 THEN DO;
		IF gro_n >= prev_gro_n THEN nb_type = 1;
		ELSE IF gro_n < prev_gro_n THEN nb_type = 2;
	END;
	ELSE nb_type = .;
RUN;



/********* 模块2: 业绩预告表数据 */
/* Step1: 当期业绩预告 */
PROC SQL;
	CREATE TABLE earning_forecast_raw AS
	SELECT trim(left(b.symbol)) AS stock_code label "stock_code",
	trim(left(b.sname)) AS stock_name label "stock_name",
	a.forecastsession, a.forecastbasesession,
	a.reportdate, a.efct9, a.efct10, a.efct11, a.efct12, a.efct14, a.efct15, a.efct16, a.efct17, a.reportunit
	FROM gogoal.efct AS a LEFT JOIN gogoal.securitycode AS b 
	ON  a.companycode = b.companycode
   	WHERE b.stype = 'EQA'
	AND reportdate>= "&minDate.:00:00:00"dt and reportdate<="&maxDate.:00:00:00"dt
	ORDER BY stock_code, A.reportdate;
QUIT;

DATA earning_forecast_raw(drop = period_type period_year period_year_o forecastsession forecastbasesession reportunit);
	SET earning_forecast_raw;
	primary_key = _N_;
	period_type = substr(forecastsession,5,1);
	IF stock_name ~= "上药转换"    /*剔除权证和上药转换*/
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
		
	*单位转换;
    IF reportunit='百万' THEN DO; 
		efct9=efct9*1000000;
		efct15=efct15*1000000;	
    END; 
	ELSE IF reportunit='千元' THEN DO;
    		efct9=efct9*1000;
			efct15=efct15*1000;				
    END; 
	ELSE IF reportunit='万元' THEN DO;
    		efct9=efct9*10000;
			efct15=efct15*10000;				
    END;
    ELSE IF reportunit='元' THEN DO;
    		efct9=efct9*1;
			efct15=efct15*1;				
    END;    
	ELSE IF reportunit='亿' or reportunit='亿元' THEN DO;
    		efct9=efct9*10000000;
			efct15=efct15*100000000;				
    END; 

	reportdate = datepart(reportdate);

	RENAME reportdate = report_date efct14 = source efct11 = earning_des
			efct9 = eup_num efct10 = eup_ratio efct12 = eup_type 
			efct15 = elow_num efct16 = elow_ratio efct17 = elow_type;
	LABEL reportdate= "report_date";
	LABEL efct14 ="source";
	LABEL efct11 ="earning_des";
	LABEL efct9 ="eup_num";
	LABEL efct10= "eup_ratio";
	LABEL efct12= "eup_type";
	LABEL efct15= "elow_num";
	LABEL efct16="elow_ratio";
	LABEL efct17 ="elow_type";
	FORMAT reportdate mmddyy10.;
RUN;

/* 匹配业绩预告中基期的真实业绩增长率，以计算更为准确的增长上下限 */
PROC SQL;
	CREATE TABLE tmp AS
	SELECT A.*,b.earning_n 
	FROM earning_forecast_raw a LEFT JOIN
	(
	SELECT stock_code, report_period, report_date, earning_n
	FROM earning_actual_raw
	)b
	ON a.stock_code = b.stock_code AND a.report_period_o = b.report_period
	AND a.report_date >= B.report_date
	ORDER BY primary_key;
QUIT;

DATA  earning_forecast_raw ;  /* 保留基期的净利润 */
	SET tmp;

    /*计算增长率(只针对所有正收益率）*/;
	IF earning_n>0 and eup_num>0 THEN eup_ratio_c = round((eup_num-earning_n)/abs(earning_n)*100,0.01);		
	IF earning_n>0 and elow_num>0 THEN elow_ratio_c = round((elow_num-earning_n)/abs(earning_n)*100,0.01); 		
  	
	is_up_original = 1;
	is_low_original = 1;

	/*定义最后的增长率-上限(是否依赖计算所得）*/;
    IF NOT MISSING(eup_ratio) AND eup_ratio~= 0 THEN eup_ratio_f=eup_ratio;
/*    IF NOT MISSING(eup_ratio) THEN eup_ratio_f=eup_ratio;*/  /** 提供给方旻的服务器版本，目前用的是这个 */
    ELSE DO;
   	  eup_ratio_f=eup_ratio_c;	
	  is_up_original = 0;
    END;

   /*定义最后的增长率-下限*/
   IF NOT MISSING(elow_ratio) AND elow_ratio ~= 0 THEN elow_ratio_f=elow_ratio; 
/* IF NOT MISSING(elow_ratio)  THEN elow_ratio_f=elow_ratio; */  /** 提供给方旻的服务器版本，目前用的是这个 */
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
/** 对2010年以前的数据，影响较大 */
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
   KEEP primary_key stock_code stock_name report_date report_period source earning_des
      eup_type eup elow_type elow f_type is_up_original is_low_original;
RUN;

/* Step2: （已发布的）最近季度的财报数据*/
/* 特例：若现在公布半年报数据，而历史已公布数据中：A去年年报滞后于当年一季度报，则仍选取一季报结果*/
/** 不对report_period之间的相对关系有限制。避免(1)的情况发生 */
/**
注意对于(1)(2)两种情况，最近季度的财报数据不可跟当前期业绩预告比较。该信号无意义 */
/** 
(1) 财报期数 > 业绩预告期数: 出现3个outlier
(a) 600550(*ST天威) 2008/12/30发布20080630(source=05)的业绩预告。--> 从描述信息来看，录入有问题。应该是20081231的业绩预告
(b) 300199(韩宇药业) 2013/3/15发布20120331(source=05)的业绩预告。--> 从描述信息来看，录入有问题。应该是20130331的业绩预告
(c) 002160(*ST常铝) 2013/4/20发布20121231(source =05)的业绩预告。同一天已发布20130331的财报。

(2) 财报期数 = 业绩预告期数: 认为is_pub=0，不发出买入信号。这时候的信号都认为是无意义的 
(a) 样本数: 115

(3) 财报期 < 业绩预告期：
(a) 43771 (大多数)

**/
PROC SQL;
	CREATE TABLE earning_forecast_merge AS
	SELECT A.*, B.report_period AS a_report_period LABEL "a_report_period", 
		B.report_date AS a_report_date LABEL "a_report_date",
		B.gro_n AS a_gro_n LABEL "a_gro_n",
		B.e_type AS a_e_type LABEL "a_e_type"
	FROM earning_forecast_raw A LEFT JOIN 
	(
	SELECT stock_code, report_date, report_period, gro_n, e_type
	FROM earning_actual_raw
	)B
	ON A.stock_code = B.stock_code AND A.report_date>= B.report_date
	GROUP BY A.primary_key
	HAVING max(B.report_period) = B.report_period  /** 报告期优先 */
	ORDER BY B.report_period;
QUIT;


/* Step 3: （已发布）最近一期的业绩预告/
/* 特例：若现在公布半年报数据，而历史已公布数据中：A的去年年报预告滞后于当年一季度报预告，则仍选取一季报预告结果*/
/* 最近一期业绩预告有多条公布记录，优先序：公布时间>临时公告>3季度报>半年报>1季度报 */

/** 要求: a.report_period > b.report_period的原因是: 避免抓取到同期的业绩预告。(主要是为了比较)
另外历史上也曾有500多条记录，先发布的预告期大于当前预告期，其中有400多条在同一天发布。另外100多天是提前发生的 */

PROC SQL;
	CREATE TABLE tmp AS
	SELECT A.*, B.primary_key AS prev_key "prev_key", 
		B.report_date AS prev_report_date  LABEL "prev_report_date", 
		B.report_period AS prev_report_period LABEL "prev_report_period",
		B.source AS prev_source  LABEL "prev_source", 
		B.eup_type AS prev_eup_type LABEL "prev_eup_type",
		B.eup AS prev_eup LABEL "prev_eup",
		B.elow_type AS prev_elow_type LABEL "prev_elow_type",
		B.elow AS prev_elow LABEL "prev_elow",
		 B.f_type AS prev_f_type LABEL "prev_f_type"
	FROM earning_forecast_merge A LEFT JOIN 
	(
	SELECT primary_key, stock_code, report_date, report_period, 
			source, eup_type, eup, elow_type, elow, f_type
	FROM earning_forecast_raw
	)B
	ON A.stock_code = B.stock_code  AND A.report_date >= B.report_date AND A.report_period > B.report_period 
	GROUP BY A.primary_key
	HAVING B.report_period = max(B.report_period); /** 先选报告期最近的 */
QUIT;
PROC SQL;	
	CREATE TABLE earning_forecast_merge AS
	SELECT *
	FROM 
	(
	SELECT *
	FROM tmp
	GROUP BY primary_key
	HAVING prev_report_date = max(prev_report_date)   /** 选日期最近的 */
	)
	GROUP BY primary_key
	HAVING prev_source = max(prev_source)  /* 选来源 */
	ORDER BY primary_key;
QUIT;



/** appendix:目的是为了设置退出时点 **/

/** Step3-appendix1: 补充，（未发布）最近发生的财报数据*/
/****  
Q1: 是否要包含“同一时间发布”的条件?  --> 否（因为(1a)和(1b)在之前会被识别出，可以判别出是否为准确的买点。而(1c)中这样的财报不应该成为退出时点)
	因为：认为“先有一季报业绩预告，然后才公布去年年报”，年报也不应该作为退出时点，而仍是应该以1季度财报为退出时点。所以可以整类直接删除。
Q2: 是否需要财报期>预告期?  --> 要。这样可以避免错误的将(1c)和(2c)作为退出时点。最终发生信号，并能有准确退出信号的有 (2a)和(2b) **/

/** 统计: 
(1)财报和业绩预告同时发布的情况包括:
(a) 财报期>预告期: (只有3个outlier)
(b) 财报期=预告期: 大多是一季报时候发生，偶尔也有其他情况/
(c) 财报期 <预告期：（占比较大，正常的状况）

(2) 财报晚于业绩预告情况包括:
(a) 财报期 > 预告期：年报预告发布后，最近发布的财报为下一年的一季报。（而不是当期）。其他情况也偶尔发生。
(b) 财报期 = 预告期：（最多的情况，正常的状况）
(c) 财报期 < 预告期: 先发一季预告，再发去年的年报。其他情况也偶尔发生。
**/

PROC SQL;
	CREATE TABLE tmp AS
	SELECT A.*, B.report_date AS next_a_report_date LABEL "next_a_report_date", 
		B.report_period AS next_a_report_period LABEL "next_a_report_period"
	FROM earning_forecast_merge A LEFT JOIN 
	(
	SELECT stock_code, report_date, report_period
	FROM earning_actual_raw
	) B
	ON A.stock_code = B.stock_code AND B.report_date > A.report_date 
	GROUP BY A.primary_key
	HAVING B.report_date = min(B.report_date);
QUIT;

/** 因为存在一种可能是：同一天发布不同期的财报，仅保留报告期最大的那条记录 */
PROC SQL;
	CREATE TABLE earning_forecast_merge AS
	SELECT *
	FROM tmp
	GROUP BY primary_key 
	HAVING next_a_report_period = max(next_a_report_period)
	ORDER BY primary_key;
QUIT;

/** Step3-appendix2: 补充，（未发布）最近发生的业绩预告时间*/
/** 这里对report_period没有要求。因为无论是什么时期发生的业绩事件，其都应作为退出信号处理 */
PROC SQL;
	CREATE TABLE tmp AS
	SELECT A.*, B.primary_key AS next_key LABEL "next_key",
		B.report_date AS next_f_report_date LABEL "next_f_report_date",
		B.report_period AS next_f_report_period LABEL "next_f_report_period"
	FROM earning_forecast_merge A LEFT JOIN
	(SELECT primary_key, stock_code, report_date, report_period
	FROM earning_forecast_raw
	)B
	ON A.stock_code = B.stock_code AND A.report_date < B.report_date
	GROUP BY A.primary_key
	HAVING B.report_date = min(B.report_date);
QUIT;

PROC SQL;	
	CREATE TABLE earning_forecast_merge AS
	SELECT *
	FROM 
	(
	SELECT *
	FROM tmp
	GROUP BY primary_key
	HAVING  next_f_report_period = min(next_f_report_period)   /** 选期数最近的 */
	)
	GROUP BY primary_key
	HAVING next_key = min(next_key)  /* 只是为了保证一对一的关系，没有任何筛选要求 */
	ORDER BY primary_key;
QUIT;


/* Step 4: 完善基础信号: choose + is_valid + is_qoq */
/* 基础信号共4个（信号值不缺失）：*/
/** is_pub: 1- 当期或者下N期已经有财报发布。 0- 未发布 */
/* choose: 1-以真实公告为比较基准，0-以前期业绩预告为比较基准；当之前没有任何比较基准允许缺失，*/
/* is_valid: 1-比较基准有意义，0-比较基准无意义（比较基准超过一年，或者财报已发布） */
/* is_qoq: 1- 恰好是季度环比，0- 不是相邻季度的环比 */

DATA earning_forecast_merge;
	SET earning_forecast_merge;
	IF not missing(a_report_period) AND input(report_period,8.) <= input(a_report_period, 8.) THEN is_pub = 1;
	ELSE is_pub = 0;

	/* 建立业绩链比较基准： 1-（本期或前期）真实业绩公告， 0-前期业绩预告*/
	IF NOT MISSING(prev_report_period) AND NOT MISSING(a_report_period) THEN DO;
		IF input(prev_report_period,8.) <= input(a_report_period,8.) THEN choose = 1; 
		ELSE choose = 0; 
	END;
	ELSE IF NOT MISSING(prev_report_period) THEN choose = 0;
	ELSE IF NOT MISSING(a_report_period) THEN choose = 1;
	ELSE choose = -1;  /** 无法选 */
	
	IF choose = 1 THEN cmp_period = a_report_period;
	ELSE IF choose = 0 THEN cmp_period = prev_report_period;
	ELSE cmp_period = .;

	/* 相隔时间超过1年，比较基准失效*/
	IF NOT MISSING(cmp_period) THEN DO;
		IF input(report_period,8.)-input(cmp_period,8.)>10000 OR input(report_period,8.)-input(cmp_period,8.)<= 0 THEN /* 如果已发布则视为失效 */
			is_valid = 0;
    	ELSE is_valid = 1;
	END;
	ELSE is_valid = 0;
	
	IF is_valid = 1 THEN DO;
		IF input(report_period,8.)-input(cmp_period,8.) IN (301,300,299,9100)  THEN is_qoq = 1;
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
	ELSE is_signal = 0;

	/* 3- is_improve: 创建改善与否信号（前提：is_signal = 1) */
	/* 1- 绝对改善，0-不确定，-1-绝对恶化，2-数据本身不确定性强*/
	IF is_signal = 1 THEN DO;
		IF choose = 1 THEN DO; /*真实财报*/
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
				ELSE is_improve = 0; 
			END;
		END;
		ELSE DO; /*前期预告*/
			IF NOT MISSING(eup) AND NOT MISSING(elow) AND NOT MISSING(prev_eup) AND NOT MISSING(prev_elow) THEN DO;
				IF elow >= prev_eup THEN is_improve = 1;
				ELSE IF eup <= prev_elow THEN is_improve = -1;
				ELSE is_improve = 0;
/*				IF elow > prev_elow AND eup >= prev_eup THEN is_improve = 1;*/   /**　整个区间移动 */
/*				ELSE is_improve = -1;*/
			END;
			ELSE IF NOT MISSING(eup) AND NOT MISSING(elow) AND NOT MISSING(prev_eup) THEN DO; /* 前一期无下限*/
				IF elow >= prev_eup THEN is_improve = 1;
				ELSE is_improve = 0;
/*				IF eup >= prev_eup THEN is_improve = 1;*/
/*				ELSE is_improve = -1;*/
			END;
			ELSE IF NOT MISSING(eup) AND NOT MISSING(elow) AND NOT MISSING(prev_elow) THEN DO; /* 前一期无上限 */
				IF eup <= prev_elow THEN is_improve = -1;
				ELSE is_improve = 0;
/*				is_improve = -1;*/
			END;	
			ELSE IF NOT MISSING(elow) AND NOT MISSING(prev_eup) AND NOT MISSING(prev_elow) THEN DO; /* 当期无上限 */
				IF elow >= prev_eup THEN is_improve = 1;
				ELSE is_improve = 0;
/*				IF elow > prev_elow THEN is_improve = 1;*/
/*				ELSE is_improve = -1;*/
			END;
			ELSE IF NOT MISSING(eup) AND NOT MISSING(prev_eup) AND NOT MISSING(prev_elow) THEN DO;  /* 当期无下限 */
				IF eup <= prev_elow THEN is_improve = -1; 
				ELSE is_improve = 0;
/*				is_improve = -1;*/
			END;
			ELSE is_improve = 2; /* too many uncertainty */
		END;
	END;
	ELSE is_improve = 3; /** 信号无意义 **/
RUN;


/******* 模块3: 完善利润表（与当期的业绩预告结合）****/
/** （已发布的) 最近季度的业绩预告数据 **/
/** 因为有可能下N期的业绩预告已出，不作为比较对象。故需要: A.report_period >= B.report_period  */
PROC SQL;
	CREATE TABLE tmp AS
	SELECT A.*, B.primary_key AS pf_key LABEL "pf_key",
		B.report_date AS pf_report_date LABEL "pf_report_date", 
		B.report_period AS pf_report_period LABEL "pf_report_date", 
		B.source AS pf_source LABEL "pf_source",
		B.eup AS pf_eup LABEL "pf_eup",
		B.eup_type AS pf_eup_type LABEL "pf_eup_type",
		B.elow AS pf_elow LABEL "pf_elow",
		B.elow_type AS pf_elow_type LABEL "pf_elow_type",
		B.f_type AS pf_f_type LABEL "pf_f_type"
		FROM earning_actual_merge A LEFT JOIN 
		(SELECT primary_key, stock_code, report_date, report_period, source, eup, eup_type,
			elow, elow_type, f_type
		FROM earning_forecast_raw
		)B
		ON A.stock_code = B.stock_code AND  A.report_date>=B.report_date AND A.report_period >= B.report_period 
		GROUP BY A.primary_key
		HAVING max(B.report_period) = B.report_period;
QUIT;
PROC SQL;	
	CREATE TABLE earning_actual_merge AS
	SELECT *
	FROM 
	(
	SELECT *
	FROM tmp
	GROUP BY primary_key
	HAVING pf_report_date = max(pf_report_date)   /** 选日期最近的 */
	)
	GROUP BY primary_key
	HAVING pf_source = max(pf_source)  /* 选来源 */
	ORDER BY primary_key;
QUIT;


DATA earning_actual_merge;
	SET earning_actual_merge;
	/* 建立业绩链比较基准： 1-最近真实业绩公告， 0-最近业绩预告*/
	IF NOT MISSING(prev_report_period) AND NOT MISSING(pf_report_period) THEN DO;
		IF input(pf_report_period,8.) <= input(prev_report_period,8.) THEN choose = 1; 
		ELSE choose = 0; 
	END;
	ELSE IF NOT MISSING(pf_report_period) THEN choose = 0;
	ELSE IF NOT MISSING(prev_report_period) THEN choose = 1;
	ELSE choose = -1;
	
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
	
	IF is_valid = 1 AND choose = 1 THEN DO;
		IF input(report_period,8.)-input(cmp_period,8.) IN (301,300,299,9100) THEN is_qoq = 1; 
		ELSE is_qoq = 0;
	END;
	ELSE IF is_valid = 1 AND choose = 0 THEN DO;
		IF input(report_period,8.)-input(cmp_period,8.) IN (301,300,299,9100) THEN is_qoq = 1;  
		ELSE IF report_period = cmp_period THEN is_qoq = 2; /** 与当期的业绩预告相比，视为"超预期" **/  
		ELSE is_qoq = 0;
	END;
	ELSE is_qoq = 0;
RUN; 

/* Step 5: 构造间接信号 */
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
	ELSE is_signal = 0;

	/* 3- is_improve: 创建改善与否信号（前提：is_signal = 1) */
	/* 1- 绝对改善，0-不确定，-1-绝对恶化，2-数据本身不确定性强*/
	IF is_signal = 1 THEN DO;
		IF choose = 1 THEN DO; /*真实业绩*/
			IF	gro_n >= prev_gro_n THEN is_improve = 1;
			ELSE is_improve = -1;
		END;
		ELSE DO; /*前期预告*/
			IF NOT MISSING(pf_eup) AND NOT MISSING(pf_elow) THEN DO;
				IF gro_n >= pf_eup THEN is_improve = 1;  
				ELSE IF gro_n >= pf_elow THEN is_improve = 0;
				ELSE is_improve = -1;
			END;
			ELSE IF missing(pf_elow) THEN DO; /* 前一期无下限，只能以上线为比较标准*/
				IF gro_n >= pf_eup THEN is_improve = 1;
				ELSE is_improve = 0;
			END;
			ELSE IF missing(pf_eup) THEN DO; /* 前一期无上限 */
				IF gro_n < pf_elow THEN is_improve = -1;
				ELSE is_improve = 0;
			END;	
		END;
	END;
	ELSE is_improve = 3; 
RUN;



/** appendix:目的是为了设置退出时点 **/
/** Step3-appendix1: 补充，（未发布）最近发生的财报数据*/

PROC SQL;
	CREATE TABLE tmp AS
	SELECT A.*, B.report_date AS next_a_report_date LABEL "next_a_report_date", 
		B.report_period AS next_a_report_period LABEL "next_a_report_period"
	FROM earning_actual_merge A LEFT JOIN 
	(
	  SELECT stock_code, report_date, report_period
	  FROM earning_actual_raw
	)B
	ON A.stock_code = B.stock_code AND B.report_date > A.report_date 
	GROUP BY A.primary_key
	HAVING B.report_date = min(B.report_date);
QUIT;

/** 因为存在一种可能是：同一天发布不同期的财报，仅保留报告期最大的那条记录 */
PROC SQL;
	CREATE TABLE earning_actual_merge AS
	SELECT *
	FROM tmp
	GROUP BY primary_key 
	HAVING next_a_report_period = max(next_a_report_period)
	ORDER BY primary_key;
QUIT;

/** Step3-appendix2: 补充，（未发布）最近发生的业绩预告时间*/
/** 这里对report_period没有要求。因为无论是什么时期发生的业绩事件，其都应作为退出信号处理 */
PROC SQL;
	CREATE TABLE tmp AS
	SELECT A.*, B.primary_key AS next_key LABEL "next_key",
		B.report_date AS next_f_report_date LABEL "next_f_report_date",
		B.report_period AS next_f_report_period LABEL "next_f_report_period"
	FROM earning_actual_merge A LEFT JOIN
	(
	SELECT primary_key, stock_code, report_date, report_period
	FROM earning_forecast_raw
	)B
	ON A.stock_code = B.stock_code AND A.report_date < B.report_date
	GROUP BY A.primary_key
	HAVING B.report_date = min(B.report_date);
QUIT;

PROC SQL;	
	CREATE TABLE earning_actual_merge AS
	SELECT *
	FROM 
	(
	SELECT *
	FROM tmp
	GROUP BY primary_key
	HAVING  next_f_report_period = min(next_f_report_period)   /** 选期数最近的 */
	)
	GROUP BY primary_key
	HAVING next_key = min(next_key)  /* 只是为了保证一对一的关系，没有任何筛选要求 */
	ORDER BY primary_key;
QUIT;

PROC SQL;
	DROP TABLE tmp, earning_forecast_raw, earning_actual_raw, earning_actual;
QUIT;


