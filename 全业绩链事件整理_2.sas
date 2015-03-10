/* ������ */

%INCLUDE  "D:\Research\CODE\sascode\event\��������\date_macro.sas";

/* ����A�� */
/*PROC SQL;*/
/*	CREATE TABLE a_stock_list AS*/
/*	SELECT distinct stock_code*/
/*	FROM hq.hqinfo*/
/*	WHERE type = "A"*/
/*	ORDER BY stock_code;*/
/*QUIT;*/

/* �ų�δ���й�Ʊ */
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


/* ������ */
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


/******* ģ��1:  �����*/
/* Step1: �������� */
PROC SQL;
	CREATE TABLE earning_actual  AS
	SELECT f16_1090 AS stock_code ,ob_object_name_1090 AS stock_name,f2_1854 AS report_period,f3_1854 AS report_date_2, 
		f61_1854 AS earning_n
	FROM locwind.tb_object_1854 AS a LEFT JOIN locwind.TB_OBJECT_1090 AS b 
	ON a.F1_1854 = b.OB_REVISIONS_1090  
  	WHERE b.f4_1090='A' AND a.f4_1854='�ϲ�����' AND input(A.F3_1854,8.) >= 20040000 AND B.F16_1090 IN     /** ��2006�꿪ʼ���в��Ի��� */
	(SELECT stock_code FROM a_stock_list);

	CREATE TABLE earning_actual_raw AS
	SELECT a.*, b.report_period AS report_period_o, b.earning_n AS earning_o, 
		round((a.earning_n - b.earning_n)/abs(b.earning_n)*100, 0.01) AS gro_n
	FROM earning_actual AS a LEFT JOIN earning_actual AS b
	ON input(a.report_period,8.) - 10000 = input(b.report_period,8.) AND a.stock_code = b.stock_code
	ORDER BY a.stock_code, a.report_period;
QUIT;

/* Step2: ͬ������ */
DATA earning_actual_raw(drop = report_date_2);
	SET earning_actual_raw;
	report_date = input(trim(left(report_date_2)),yymmdd8.);
	report_period = trim(left(report_period));
	format report_date mmddyy10.;
	/*ӯ�����ࣺ1Ϊ��������2ΪŤ����3Ϊ�׿���4Ϊ������ӯ�� */
	IF NOT MISSING (earning_o) AND NOT missing(earning_n) THEN DO;
		IF earning_o<=0 and earning_n<=0 THEN DO;
			e_type=1;
/*			gro_n = .;   ������Ч */
		END; 
   		ELSE IF earning_o<=0 and earning_n>0 THEN DO;
			e_type=2;
/*			gro_n = .;*/
		END;
   		ELSE IF  earning_o>0 and earning_n<=0 THEN DO;
			e_type=3;
/*			gro_n = .;  ������Ч */
		END;
    	ELSE IF  earning_o>0 and earning_n>0 THEN e_type=4;
	END;
	ELSE e_type = .;
RUN;

/* Step3: (�ѷ�����)������ȵ���������: */
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



/* Step4: ���ڼ��ȣ����ٵĻ�������*/
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


/* ����ͨ��: ���ͬһ�������ڣ��������ظ�ֵ*/
/*PROC SORT DATA = earning_actual_merge NODUPKEY;*/
/*	BY stock_code report_period;*/
/*RUN;*/

/* ��ʱ��ȥ�� */
/* �����ظ��۲�ֵ����Ϊ�������걨����ͬʱ���档�������¹����ڵ����� */

PROC SORT DATA = earning_actual_merge;
	BY stock_code report_date descending report_period;
RUN;

/*PROC SORT DATA = earning_actual_merge NODUPKEY;*/
/*	BY stock_code report_date;*/
/*RUN;  */



	
/********* ģ��2: ҵ��Ԥ������� */
/* Step1: ����ҵ��Ԥ�� */
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
	IF (substr(stock_code,1,1) = "0" OR substr(stock_code,1,1) = "6")  /* A�� */
	AND substr(stock_code,1,2) ~= "03" AND  stock_name ~= "��ҩת��"    /*�޳�Ȩ֤����ҩת��*/
	AND period_type="3" or period_type="1" or period_type="4" or period_type="2"  /*���ݴ����޳�������Ԥ��Ͷ�������*/
	AND not missing(efct11)
	AND (not missing(efct9) OR not missing(efct10) OR not missing(efct15) OR not missing(efct16)); /* ������Ҫ�����������ʻ����ֵ��һ������)*/
	period_year = input(substr(forecastsession,1,4),8.);
	period_year_o = input(substr(forecastsession,1,4),8.)-1;
	IF  input(substr(forecastsession,1,5),8.)- input(substr(forecastbasesession,1,5),8.)=10;  /* ֻ����ͬ������ */
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

/* ƥ��ҵ��Ԥ���л��ڵ���ʵҵ�������ʣ��Լ����Ϊ׼ȷ������������ */
PROC SQL;
	CREATE TABLE tmp AS
	SELECT A.*,b.earning_n 
	FROM earning_forecast_raw a LEFT JOIN earning_actual_raw b
	ON trim(left(a.stock_code)) = trim(left(b.stock_code)) AND a.report_period_o = b.report_period;
QUIT;

DATA  earning_forecast_raw(rename = (earning_n = base_earning_n)) ;  /* �������ڵľ����� */
	SET tmp;
	report_date = datepart(report_date);
	FORMAT report_date mmddyy10.;
	*��λת��;
    IF reportunit='����' THEN DO; 
		eup_num=eup_num*1000000;
		elow_num=elow_num*1000000;	
    END; 
	ELSE IF reportunit='ǧԪ' THEN DO;
    		eup_num=eup_num*1000;
			elow_num=elow_num*1000;				
    END; 
	ELSE IF reportunit='��Ԫ' THEN DO;
    		eup_num=eup_num*10000;
			elow_num=elow_num*10000;				
    END;
    ELSE IF reportunit='Ԫ' THEN DO;
    		eup_num=eup_num*1;
			elow_num=elow_num*1;				
    END;    
	ELSE IF reportunit='��' or reportunit='��Ԫ' THEN DO;
    		eup_num=eup_num*10000000;
			elow_num=elow_num*100000000;				
    END; 
    
    /*����������(ֻ��������������ʣ�*/;
	IF earning_n>0 and eup_num>0 THEN eup_ratio_c = round((eup_num-earning_n)/abs(earning_n)*100,0.01);		
	IF earning_n>0 and elow_num>0 THEN elow_ratio_c = round((elow_num-earning_n)/abs(earning_n)*100,0.01); 		
  	
	is_up_original = 1;
	is_low_original = 1;

	

	/*��������������-����(�Ƿ������������ã�*/;
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

   /*��������������-����*/
   IF NOT MISSING(elow_ratio) AND elow_ratio ~= 0 THEN elow_ratio_f=elow_ratio; 
/* IF NOT MISSING(elow_ratio)  THEN elow_ratio_f=elow_ratio; */
   ELSE DO;
   	  elow_ratio_f=elow_ratio_c;	
	  is_low_original = 0;
   END;
   /* ������ԱȽϣ������˳�� */
   IF not missing(eup_ratio_f) AND not missing(elow_ratio_f) THEN DO;
   		eup = max(eup_ratio_f, elow_ratio_f);
		elow = min(eup_ratio_f, elow_ratio_f);
		IF eup_ratio_f < elow_ratio_f THEN DO;  /* ����е��������µ�����mark*/
			tmp = is_low_original;
			is_up_original = tmp;
			is_low_original = is_up_original;
		END;
   END;
   ELSE DO;
   		eup = eup_ratio_f;
		elow=elow_ratio_f;
   END;

   /** ���ݺ��壬�����ȱʧ�������� */
/*	IF missing(eup) THEN DO;*/
/*		IF eup_type IN ("Ԥӯ") THEN eup = 50;*/
/*		IF eup_type IN ("Ԥ��") THEN eup = 0;*/
/*		IF eup_type IN ("Ԥ��") THEN eup = -50;*/
/*	END;*/
/*	IF missing(elow) THEN DO;*/
/*		IF eup_type IN ("Ԥ��") THEN elow = 50;*/
/*		IF eup_type IN ("Ԥ��") THEN elow = -50;*/
/*		IF eup_type IN ("Ԥӯ") THEN elow = 0;*/
/*	END;*/

   /*���岻ͬԤ�����ͣ�0Ϊ��������С��0��1Ϊ�����������0�����޺����������壬2Ϊ�����������0����������һ��ȱʧ��3Ϊ�����������0�������޶���ȱʧ */
   IF earning_n <= 0 THEN f_type = 0;
   ELSE IF missing(eup) AND missing(elow) THEN f_type = 1;
   ELSE IF missing(eup) OR missing(elow) THEN f_type = 2;
   ELSE f_type = 3;
  
  /* ������Ҫ���ֶ� */
   KEEP efctid stock_code stock_name report_date report_period source earning_des
      eup_type eup elow_type elow f_type is_up_original is_low_original report_period_o earning_n;
RUN;

/* Step2: ���ѷ����ģ�������ȵ���ʵҵ��������*/
/* �����������ڹ������걨���ݣ�����ʷ�ѹ��������У�Aȥ���걨�ͺ��ڵ���һ���ȱ�������ѡȡһ�������*/

PROC SQL;
	CREATE TABLE tmp AS
	SELECT A.*, B.report_period AS a_report_period, B.report_date AS a_report_date,
			B.gro_n AS a_gro_n, B.e_type AS a_e_type, B.earning_n AS a_earning_n
	FROM earning_forecast_raw A LEFT JOIN earning_actual_merge B
	ON A.stock_code = B.stock_code AND A.report_period > B.report_period AND A.report_date>= B.report_date 
	ORDER BY A.efctid, B.report_period desc, B.report_date desc;
QUIT;

/* ѡȡ�����������ʵҵ��������*/
DATA earning_forecast_merge;
	SET tmp;
	BY efctid;
	IF first.efctid; 
RUN;

/** Step2-appendix: ���䣬��δ������ͬһ���ȵ���ʵҵ��������*/
/** Ŀ�ģ�Ϊ��ͳ��һ�¶��ߵ�ʱ��� **/
/*PROC SQL;*/
/*	CREATE TABLE tmp AS*/
/*	SELECT A.*, B.report_period AS same_report_period, B.report_date AS same_report_date,*/
/*			B.gro_n AS same_gro_n, B.e_type AS same_e_type, B.earning_n AS same_earning_n*/
/*	FROM earning_forecast_raw A LEFT JOIN earning_actual_merge B*/
/*	ON A.stock_code = B.stock_code AND A.report_period = B.report_period */
/*	ORDER BY A.efctid, B.report_date; */
/*QUIT;*/

/* ѡȡ�����������ʵҵ��������*/
/*DATA earning_forecast_merge;*/
/*	SET tmp;*/
/*	BY efctid;*/
/*	IF first.efctid;*/
/*RUN;*/


/* Step 3: ��֮ǰ�����һ�ڵ�ҵ��Ԥ��/
/* �����������ڹ������걨���ݣ�����ʷ�ѹ��������У�A��ȥ���걨Ԥ���ͺ��ڵ���һ���ȱ�Ԥ�棬����ѡȡһ����Ԥ����*/
/* ���һ��ҵ��Ԥ���ж���������¼�������򣺹���ʱ��>��ʱ����>3���ȱ�>���걨>1���ȱ� */

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


/* Step 4: ���ƻ����ź�: choose + is_valid + is_qoq */
/* �����źŹ�3�����ź�ֵ��ȱʧ����*/
/* choose: 1-����ʵ����Ϊ�Ƚϻ�׼��0-��ǰ��ҵ��Ԥ��Ϊ�Ƚϻ�׼����֮ǰû���καȽϻ�׼����ȱʧ��*/
/* is_valid: 1-�Ƚϻ�׼�����壬0-�Ƚϻ�׼������ */
/* is_qoq: 1- ǡ���Ǽ��Ȼ��ȣ�0- �������ڼ��ȵĻ��� */

DATA earning_forecast_merge;
	SET earning_forecast_merge;

	/* ����ҵ�����Ƚϻ�׼�� 1-�����ڻ�ǰ�ڣ���ʵҵ�����棬 0-ǰ��ҵ��Ԥ��*/
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

	/* ���ʱ�䳬��1�꣬�Ƚϻ�׼ʧЧ*/
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

/* Step 5: �������źţ��������������ź�ֵȱʧ */
DATA earning_forecast_merge(drop = d_eup d_elow);
	SET earning_forecast_merge;
	d_eup = eup - a_gro_n;
	d_elow = elow - a_gro_n;

	/* 1- is_link: ҵ�����Ƿ�������(������һ�������ޣ�ͬʱ����һ���ڵĻ��ڱȽϣ� */
	IF f_type >=2  AND is_valid = 1 THEN is_link = 1;
	ELSE is_link = 0;

	/* 2- is_signal: ��������ź��Ƿ������壨ǰ�᣺is_link = 1)*/
	/* ע�⣺ֻ���� a_e_type = 4 ������£�a_gro_n �ļ������׼ȷ�� */
	/*       ֻ���� prev_f_type >=2 ������£�prev_eup �� prev_elow ��������  */
	IF is_link = 1 THEN DO;
		IF (choose = 1 AND a_e_type = 4) OR (choose = 0 AND prev_f_type >=2) THEN is_signal = 1;
		ELSE is_signal = 0;
	END;
	ELSE is_signal = .;

	/* 3- is_improve: ������������źţ�ǰ�᣺is_signal = 1) */
	/* 1- ���Ը��ƣ�0-��ȷ����-1-���Զ񻯣�2-���ݱ���ȷ����ǿ*/
	IF is_signal = 1 THEN DO;
		IF choose = 1 THEN DO; /*��ʵҵ��*/
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
				ELSE is_improve = -1;  /* �����޸�Ϊ-1����Ϊ��ȷ����̫ǿ */
			END;
		END;
		ELSE DO; /*ǰ��Ԥ��*/
			IF NOT MISSING(eup) AND NOT MISSING(elow) AND NOT MISSING(prev_eup) AND NOT MISSING(prev_elow) THEN DO;
/*				IF elow >= prev_eup THEN is_improve = 1;*/
/*				ELSE IF eup <= prev_elow THEN is_improve = -1;*/
/*				ELSE is_improve = 0;*/
				IF elow > prev_elow AND eup >= prev_eup THEN is_improve = 1;
				ELSE is_improve = -1;
			END;
			ELSE IF NOT MISSING(eup) AND NOT MISSING(elow) AND NOT MISSING(prev_eup) THEN DO; /* ǰһ��������*/
/*				IF elow >= prev_eup THEN is_improve = 1;*/
/*				ELSE is_improve = 0;*/
				IF eup >= prev_eup THEN is_improve = 1;
				ELSE is_improve = -1;
			END;
			ELSE IF NOT MISSING(eup) AND NOT MISSING(elow) AND NOT MISSING(prev_elow) THEN DO; /* ǰһ�������� */
/*				IF eup <= prev_elow THEN is_improve = -1;*/
/*				ELSE is_improve = 0;*/
				is_improve = -1;
			END;	
			ELSE IF NOT MISSING(elow) AND NOT MISSING(prev_eup) AND NOT MISSING(prev_elow) THEN DO; /* ���������� */
/*				IF elow >= prev_eup THEN is_improve = 1;*/
/*				ELSE is_improve = 0;*/
				IF elow > prev_elow THEN is_improve = 1;
				ELSE is_improve = -1;
			END;
			ELSE IF NOT MISSING(eup) AND NOT MISSING(prev_eup) AND NOT MISSING(prev_elow) THEN DO;  /* ���������� */
/*				IF eup <= prev_elow THEN is_improve = -1; */
/*				ELSE is_improve = 0;*/
				is_improve = -1;
			END;
			ELSE is_improve = 2; /* too many uncertainty */
		END;
	END;
	ELSE is_improve = .;
RUN;

/******* ģ��3: ����������뵱�ڵ�ҵ��Ԥ���ϣ�*/
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



/** ���ѷ�����) ������ȵ�ҵ��Ԥ������ **/
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
	/* ����ҵ�����Ƚϻ�׼�� 1-�����ʵҵ�����棬 0-���ҵ��Ԥ��*/
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

	/* ���ʱ�䳬��1�꣬�Ƚϻ�׼ʧЧ*/
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

/* Step 5: �������źţ��������������ź�ֵȱʧ */
DATA earning_actual_merge;
	SET earning_actual_merge;

	/* 1- is_link: ҵ�����Ƿ�������(ֻ���ǳ���ӯ�����������ʱ��gro_n�����壩 */
	IF e_type =4  AND is_valid = 1 THEN is_link = 1;
	ELSE is_link = 0;

	/* 2- is_signal: ��������ź��Ƿ������壨ǰ�᣺is_link = 1)*/
	/* ע�⣺ֻ���� prev_e_type = 4 ������£�prev_gro_n �ļ������׼ȷ�� */
	/*       ֻ���� pf_f_type >=2 ������£�pf_eup �� pf_elow ��������  */
	IF is_link = 1 THEN DO;
		IF (choose = 1 AND prev_e_type = 4) OR (choose = 0 AND pf_f_type >=2) THEN is_signal = 1;
		ELSE is_signal = 0;
	END;
	ELSE is_signal = .;

	/* 3- is_improve: ������������źţ�ǰ�᣺is_signal = 1) */
	/* 1- ���Ը��ƣ�0-��ȷ����-1-���Զ񻯣�2-���ݱ���ȷ����ǿ*/
	IF is_signal = 1 THEN DO;
		IF choose = 1 THEN DO; /*��ʵҵ��*/
			IF	gro_n >= prev_gro_n THEN is_improve = 1;
			ELSE is_improve = -1;
		END;
		ELSE DO; /*ǰ��Ԥ��*/
			IF NOT MISSING(pf_eup) AND NOT MISSING(pf_elow) THEN DO;
				IF gro_n > pf_elow THEN is_improve = 1;
				ELSE is_improve = -1;
			END;
			ELSE IF missing(pf_elow) THEN DO; /* ǰһ�������ޣ�ֻ��������Ϊ�Ƚϱ�׼*/
				IF gro_n >= pf_eup THEN is_improve = 1;
				ELSE is_improve = -1;
			END;
			ELSE IF missing(pf_eup) THEN DO; /* ǰһ�������� */
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



/********* ģ��4: �����������գ�ͬ�����ڵ�ȥ�� **/
DATA earning_actual_merge;
	SET earning_actual_merge;
	id = _N_;
RUN;
/* ����� */
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

/* ҵ��Ԥ�� */
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


/*** ģ��5: ��������/�����ź� **/
DATA actual_signal;
	SET earning_actual_clear(keep = id stock_code stock_name report_date report_period is_improve);
	IF is_improve IN (1) THEN a_signal = 1;   
	ELSE a_signal = 0;
RUN;

DATA forecast_signal(drop = eup_type);
	SET earning_forecast_clear(keep = id eup_type stock_code stock_name report_date report_period is_improve);
	IF is_improve IN (1,0) AND strip(eup_type) IN ("Ԥ��")THEN f_signal = 1;
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
			signal = a_signal; /* ����Ʊ���ҵ��Ԥ����ͬ���¼��������������ͬ�������ڣ����ԲƱ�����Ϊ׼ */
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


