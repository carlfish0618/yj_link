/*** ���빦��: ��������ҵ��Ԥ�����Ϣ�������� */

/**** �������:
(1) �����earning_actual_merge
(2)��ҵ��Ԥ���earning_forecast_merge
�����ֵ���Բο�"ҵ���¼���ʾ��˵��.txt"��
***/


%INCLUDE  "F:\Research\GIT_BACKUP\utils\date_macro.sas";

/** ���������ڿ�ʼ-������־ **/
%LET endDate = 2009-12-31;  /** �ز⿪ʼ������ */
%LET myEndDate = 31dec2009;

DATA _NULL_;
	end_date = input("&endDate.", yymmdd10.);
	y = year(end_date) - 2;
	start_date = input("31Dec"||put(y,4.),date9.);  
	act_date = input("31Dec"||put(y-1,4.),date9.);  
	/**��ҵ��Ԥ�淢��ʱ���������Сֵ��**/
	call symput("minDate", put(start_date, date9.));  
	call symput("maxDate","01Jan2100");  
	/** �Ʊ�����ʱ���������Сֵ **/
	call symput("actMinDate",put(act_date,yymmddn8.));
	call symput("actMaxDate","21000101");  
	call symput("actMinDate2",put(start_date,yymmddn8.));   
RUN;




/************************** ģ��1:  �����***********/
/*** primary key: (stock_code, report_period) */ 
/* ����ͨ��: ���ͬһ�������ڣ��������ظ�ֵ*/
/*PROC SORT DATA = earning_actual_merge NODUPKEY;*/
/*	BY stock_code report_period;*/
/*RUN;*/

/* Step1: �������� */
PROC SQL;
	CREATE TABLE earning_actual  AS
	SELECT trim(left(f16_1090)) AS stock_code LABEL "stock_code" ,
			ob_object_name_1090 AS stock_name LABEL "stock_name",
			trim(left(f2_1854)) AS report_period LABEL "report_period",
			input(trim(left(f3_1854)),yymmdd8.) AS report_date LABEL "report_date" FORMAT mmddyy10.,
			f61_1854 AS earning_n LABEL "earning_n"
	FROM locwind.tb_object_1854 AS a LEFT JOIN locwind.TB_OBJECT_1090 AS b 
	ON a.F1_1854 = b.OB_REVISIONS_1090  
  	WHERE b.f4_1090='A' AND a.f4_1854='�ϲ�����' AND A.F2_1854 >= "&actMinDate"  AND A.F2_1854 <=  "&actMaxDate";

	CREATE TABLE earning_actual_raw AS
	SELECT a.*, b.report_period AS report_period_o LABEL "report_period_o",
			b.earning_n AS earning_o LABEL "earning_o", 
			round((a.earning_n - b.earning_n)/abs(b.earning_n)*100, 0.01) AS gro_n
	FROM earning_actual AS a LEFT JOIN earning_actual AS b
	ON input(a.report_period,8.) - 10000 = input(b.report_period,8.) AND a.stock_code = b.stock_code
	AND a.report_date >= b.report_date
	WHERE a.report_period >= "&actMinDate2"  /** ��ȡͬ�ȵĵڶ��꿪ʼ */
	ORDER BY a.stock_code, a.report_period;
QUIT;

/* Step2: ͬ������ */
DATA earning_actual_raw;
	SET earning_actual_raw;
	primary_key = _N_;
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
/** ��Tʱ�㣬����������Ѿ�����T+1ʱ��ĲƱ����棨����a.report_period > b.report_period�Ƿ����Ӷ�����)**/

PROC SQL;
	CREATE TABLE earning_actual_merge AS
	SELECT A.*, B.report_period AS prev_report_period LABEL "prev_report_period", 
		B.report_date AS prev_report_date LABEL "prev_report_date", 
		B.gro_n AS prev_gro_n LABEL "prev_gro_n",
		B.e_type AS prev_e_type LABEL "prev_e_type" 
	FROM earning_actual_raw A LEFT JOIN 
	(
	SELECT stock_code, report_period, report_date, gro_n, e_type   /** ѡ�Ӽ������ٶȱ�� */
	FROM earning_actual_raw
	)B
	ON a.report_period > b.report_period AND A.stock_code = B.stock_code AND a.report_date >= b.report_date 
	GROUP BY A.primary_key
	HAVING max(B.report_period) = B.report_period 
	ORDER BY primary_key;
QUIT;


/****** �������û�б�Ҫ����Ϊ�ܿ��ܺ͡�������ȵ��������ݡ��غ�) ***/
/* Step4: ���ڼ��ȣ����ٵĻ�������*/
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



/********* ģ��2: ҵ��Ԥ������� */
/* Step1: ����ҵ��Ԥ�� */
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
	IF stock_name ~= "��ҩת��"    /*�޳�Ȩ֤����ҩת��*/
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
		
	*��λת��;
    IF reportunit='����' THEN DO; 
		efct9=efct9*1000000;
		efct15=efct15*1000000;	
    END; 
	ELSE IF reportunit='ǧԪ' THEN DO;
    		efct9=efct9*1000;
			efct15=efct15*1000;				
    END; 
	ELSE IF reportunit='��Ԫ' THEN DO;
    		efct9=efct9*10000;
			efct15=efct15*10000;				
    END;
    ELSE IF reportunit='Ԫ' THEN DO;
    		efct9=efct9*1;
			efct15=efct15*1;				
    END;    
	ELSE IF reportunit='��' or reportunit='��Ԫ' THEN DO;
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

/* ƥ��ҵ��Ԥ���л��ڵ���ʵҵ�������ʣ��Լ����Ϊ׼ȷ������������ */
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

DATA  earning_forecast_raw ;  /* �������ڵľ����� */
	SET tmp;

    /*����������(ֻ��������������ʣ�*/;
	IF earning_n>0 and eup_num>0 THEN eup_ratio_c = round((eup_num-earning_n)/abs(earning_n)*100,0.01);		
	IF earning_n>0 and elow_num>0 THEN elow_ratio_c = round((elow_num-earning_n)/abs(earning_n)*100,0.01); 		
  	
	is_up_original = 1;
	is_low_original = 1;

	/*��������������-����(�Ƿ������������ã�*/;
    IF NOT MISSING(eup_ratio) AND eup_ratio~= 0 THEN eup_ratio_f=eup_ratio;
/*    IF NOT MISSING(eup_ratio) THEN eup_ratio_f=eup_ratio;*/  /** �ṩ�����F�ķ������汾��Ŀǰ�õ������ */
    ELSE DO;
   	  eup_ratio_f=eup_ratio_c;	
	  is_up_original = 0;
    END;

   /*��������������-����*/
   IF NOT MISSING(elow_ratio) AND elow_ratio ~= 0 THEN elow_ratio_f=elow_ratio; 
/* IF NOT MISSING(elow_ratio)  THEN elow_ratio_f=elow_ratio; */  /** �ṩ�����F�ķ������汾��Ŀǰ�õ������ */
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
/** ��2010����ǰ�����ݣ�Ӱ��ϴ� */
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
   KEEP primary_key stock_code stock_name report_date report_period source earning_des
      eup_type eup elow_type elow f_type is_up_original is_low_original;
RUN;

/* Step2: ���ѷ����ģ�������ȵĲƱ�����*/
/* �����������ڹ������걨���ݣ�����ʷ�ѹ��������У�Aȥ���걨�ͺ��ڵ���һ���ȱ�������ѡȡһ�������*/
/** ����report_period֮�����Թ�ϵ�����ơ�����(1)��������� */
/**
ע�����(1)(2)���������������ȵĲƱ����ݲ��ɸ���ǰ��ҵ��Ԥ��Ƚϡ����ź������� */
/** 
(1) �Ʊ����� > ҵ��Ԥ������: ����3��outlier
(a) 600550(*ST����) 2008/12/30����20080630(source=05)��ҵ��Ԥ�档--> ��������Ϣ������¼�������⡣Ӧ����20081231��ҵ��Ԥ��
(b) 300199(����ҩҵ) 2013/3/15����20120331(source=05)��ҵ��Ԥ�档--> ��������Ϣ������¼�������⡣Ӧ����20130331��ҵ��Ԥ��
(c) 002160(*ST����) 2013/4/20����20121231(source =05)��ҵ��Ԥ�档ͬһ���ѷ���20130331�ĲƱ���

(2) �Ʊ����� = ҵ��Ԥ������: ��Ϊis_pub=0�������������źš���ʱ����źŶ���Ϊ��������� 
(a) ������: 115

(3) �Ʊ��� < ҵ��Ԥ���ڣ�
(a) 43771 (�����)

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
	HAVING max(B.report_period) = B.report_period  /** ���������� */
	ORDER BY B.report_period;
QUIT;


/* Step 3: ���ѷ��������һ�ڵ�ҵ��Ԥ��/
/* �����������ڹ������걨���ݣ�����ʷ�ѹ��������У�A��ȥ���걨Ԥ���ͺ��ڵ���һ���ȱ�Ԥ�棬����ѡȡһ����Ԥ����*/
/* ���һ��ҵ��Ԥ���ж���������¼�������򣺹���ʱ��>��ʱ����>3���ȱ�>���걨>1���ȱ� */

/** Ҫ��: a.report_period > b.report_period��ԭ����: ����ץȡ��ͬ�ڵ�ҵ��Ԥ�档(��Ҫ��Ϊ�˱Ƚ�)
������ʷ��Ҳ����500������¼���ȷ�����Ԥ���ڴ��ڵ�ǰԤ���ڣ�������400������ͬһ�췢��������100��������ǰ������ */

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
	HAVING B.report_period = max(B.report_period); /** ��ѡ����������� */
QUIT;
PROC SQL;	
	CREATE TABLE earning_forecast_merge AS
	SELECT *
	FROM 
	(
	SELECT *
	FROM tmp
	GROUP BY primary_key
	HAVING prev_report_date = max(prev_report_date)   /** ѡ��������� */
	)
	GROUP BY primary_key
	HAVING prev_source = max(prev_source)  /* ѡ��Դ */
	ORDER BY primary_key;
QUIT;



/** appendix:Ŀ����Ϊ�������˳�ʱ�� **/

/** Step3-appendix1: ���䣬��δ��������������ĲƱ�����*/
/****  
Q1: �Ƿ�Ҫ������ͬһʱ�䷢����������?  --> ����Ϊ(1a)��(1b)��֮ǰ�ᱻʶ����������б���Ƿ�Ϊ׼ȷ����㡣��(1c)�������ĲƱ���Ӧ�ó�Ϊ�˳�ʱ��)
	��Ϊ����Ϊ������һ����ҵ��Ԥ�棬Ȼ��Ź���ȥ���걨�����걨Ҳ��Ӧ����Ϊ�˳�ʱ�㣬������Ӧ����1���ȲƱ�Ϊ�˳�ʱ�㡣���Կ�������ֱ��ɾ����
Q2: �Ƿ���Ҫ�Ʊ���>Ԥ����?  --> Ҫ���������Ա������Ľ�(1c)��(2c)��Ϊ�˳�ʱ�㡣���շ����źţ�������׼ȷ�˳��źŵ��� (2a)��(2b) **/

/** ͳ��: 
(1)�Ʊ���ҵ��Ԥ��ͬʱ�������������:
(a) �Ʊ���>Ԥ����: (ֻ��3��outlier)
(b) �Ʊ���=Ԥ����: �����һ����ʱ������ż��Ҳ���������/
(c) �Ʊ��� <Ԥ���ڣ���ռ�Ƚϴ�������״����

(2) �Ʊ�����ҵ��Ԥ���������:
(a) �Ʊ��� > Ԥ���ڣ��걨Ԥ�淢������������ĲƱ�Ϊ��һ���һ�������������ǵ��ڣ����������Ҳż��������
(b) �Ʊ��� = Ԥ���ڣ������������������״����
(c) �Ʊ��� < Ԥ����: �ȷ�һ��Ԥ�棬�ٷ�ȥ����걨���������Ҳż��������
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

/** ��Ϊ����һ�ֿ����ǣ�ͬһ�췢����ͬ�ڵĲƱ�������������������������¼ */
PROC SQL;
	CREATE TABLE earning_forecast_merge AS
	SELECT *
	FROM tmp
	GROUP BY primary_key 
	HAVING next_a_report_period = max(next_a_report_period)
	ORDER BY primary_key;
QUIT;

/** Step3-appendix2: ���䣬��δ���������������ҵ��Ԥ��ʱ��*/
/** �����report_periodû��Ҫ����Ϊ������ʲôʱ�ڷ�����ҵ���¼����䶼Ӧ��Ϊ�˳��źŴ��� */
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
	HAVING  next_f_report_period = min(next_f_report_period)   /** ѡ��������� */
	)
	GROUP BY primary_key
	HAVING next_key = min(next_key)  /* ֻ��Ϊ�˱�֤һ��һ�Ĺ�ϵ��û���κ�ɸѡҪ�� */
	ORDER BY primary_key;
QUIT;


/* Step 4: ���ƻ����ź�: choose + is_valid + is_qoq */
/* �����źŹ�4�����ź�ֵ��ȱʧ����*/
/** is_pub: 1- ���ڻ�����N���Ѿ��вƱ������� 0- δ���� */
/* choose: 1-����ʵ����Ϊ�Ƚϻ�׼��0-��ǰ��ҵ��Ԥ��Ϊ�Ƚϻ�׼����֮ǰû���καȽϻ�׼����ȱʧ��*/
/* is_valid: 1-�Ƚϻ�׼�����壬0-�Ƚϻ�׼�����壨�Ƚϻ�׼����һ�꣬���߲Ʊ��ѷ����� */
/* is_qoq: 1- ǡ���Ǽ��Ȼ��ȣ�0- �������ڼ��ȵĻ��� */

DATA earning_forecast_merge;
	SET earning_forecast_merge;
	IF not missing(a_report_period) AND input(report_period,8.) <= input(a_report_period, 8.) THEN is_pub = 1;
	ELSE is_pub = 0;

	/* ����ҵ�����Ƚϻ�׼�� 1-�����ڻ�ǰ�ڣ���ʵҵ�����棬 0-ǰ��ҵ��Ԥ��*/
	IF NOT MISSING(prev_report_period) AND NOT MISSING(a_report_period) THEN DO;
		IF input(prev_report_period,8.) <= input(a_report_period,8.) THEN choose = 1; 
		ELSE choose = 0; 
	END;
	ELSE IF NOT MISSING(prev_report_period) THEN choose = 0;
	ELSE IF NOT MISSING(a_report_period) THEN choose = 1;
	ELSE choose = -1;  /** �޷�ѡ */
	
	IF choose = 1 THEN cmp_period = a_report_period;
	ELSE IF choose = 0 THEN cmp_period = prev_report_period;
	ELSE cmp_period = .;

	/* ���ʱ�䳬��1�꣬�Ƚϻ�׼ʧЧ*/
	IF NOT MISSING(cmp_period) THEN DO;
		IF input(report_period,8.)-input(cmp_period,8.)>10000 OR input(report_period,8.)-input(cmp_period,8.)<= 0 THEN /* ����ѷ�������ΪʧЧ */
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
	ELSE is_signal = 0;

	/* 3- is_improve: ������������źţ�ǰ�᣺is_signal = 1) */
	/* 1- ���Ը��ƣ�0-��ȷ����-1-���Զ񻯣�2-���ݱ���ȷ����ǿ*/
	IF is_signal = 1 THEN DO;
		IF choose = 1 THEN DO; /*��ʵ�Ʊ�*/
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
		ELSE DO; /*ǰ��Ԥ��*/
			IF NOT MISSING(eup) AND NOT MISSING(elow) AND NOT MISSING(prev_eup) AND NOT MISSING(prev_elow) THEN DO;
				IF elow >= prev_eup THEN is_improve = 1;
				ELSE IF eup <= prev_elow THEN is_improve = -1;
				ELSE is_improve = 0;
/*				IF elow > prev_elow AND eup >= prev_eup THEN is_improve = 1;*/   /**�����������ƶ� */
/*				ELSE is_improve = -1;*/
			END;
			ELSE IF NOT MISSING(eup) AND NOT MISSING(elow) AND NOT MISSING(prev_eup) THEN DO; /* ǰһ��������*/
				IF elow >= prev_eup THEN is_improve = 1;
				ELSE is_improve = 0;
/*				IF eup >= prev_eup THEN is_improve = 1;*/
/*				ELSE is_improve = -1;*/
			END;
			ELSE IF NOT MISSING(eup) AND NOT MISSING(elow) AND NOT MISSING(prev_elow) THEN DO; /* ǰһ�������� */
				IF eup <= prev_elow THEN is_improve = -1;
				ELSE is_improve = 0;
/*				is_improve = -1;*/
			END;	
			ELSE IF NOT MISSING(elow) AND NOT MISSING(prev_eup) AND NOT MISSING(prev_elow) THEN DO; /* ���������� */
				IF elow >= prev_eup THEN is_improve = 1;
				ELSE is_improve = 0;
/*				IF elow > prev_elow THEN is_improve = 1;*/
/*				ELSE is_improve = -1;*/
			END;
			ELSE IF NOT MISSING(eup) AND NOT MISSING(prev_eup) AND NOT MISSING(prev_elow) THEN DO;  /* ���������� */
				IF eup <= prev_elow THEN is_improve = -1; 
				ELSE is_improve = 0;
/*				is_improve = -1;*/
			END;
			ELSE is_improve = 2; /* too many uncertainty */
		END;
	END;
	ELSE is_improve = 3; /** �ź������� **/
RUN;


/******* ģ��3: ����������뵱�ڵ�ҵ��Ԥ���ϣ�****/
/** ���ѷ�����) ������ȵ�ҵ��Ԥ������ **/
/** ��Ϊ�п�����N�ڵ�ҵ��Ԥ���ѳ�������Ϊ�Ƚ϶��󡣹���Ҫ: A.report_period >= B.report_period  */
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
	HAVING pf_report_date = max(pf_report_date)   /** ѡ��������� */
	)
	GROUP BY primary_key
	HAVING pf_source = max(pf_source)  /* ѡ��Դ */
	ORDER BY primary_key;
QUIT;


DATA earning_actual_merge;
	SET earning_actual_merge;
	/* ����ҵ�����Ƚϻ�׼�� 1-�����ʵҵ�����棬 0-���ҵ��Ԥ��*/
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

	/* ���ʱ�䳬��1�꣬�Ƚϻ�׼ʧЧ*/
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
		ELSE IF report_period = cmp_period THEN is_qoq = 2; /** �뵱�ڵ�ҵ��Ԥ����ȣ���Ϊ"��Ԥ��" **/  
		ELSE is_qoq = 0;
	END;
	ELSE is_qoq = 0;
RUN; 

/* Step 5: �������ź� */
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
	ELSE is_signal = 0;

	/* 3- is_improve: ������������źţ�ǰ�᣺is_signal = 1) */
	/* 1- ���Ը��ƣ�0-��ȷ����-1-���Զ񻯣�2-���ݱ���ȷ����ǿ*/
	IF is_signal = 1 THEN DO;
		IF choose = 1 THEN DO; /*��ʵҵ��*/
			IF	gro_n >= prev_gro_n THEN is_improve = 1;
			ELSE is_improve = -1;
		END;
		ELSE DO; /*ǰ��Ԥ��*/
			IF NOT MISSING(pf_eup) AND NOT MISSING(pf_elow) THEN DO;
				IF gro_n >= pf_eup THEN is_improve = 1;  
				ELSE IF gro_n >= pf_elow THEN is_improve = 0;
				ELSE is_improve = -1;
			END;
			ELSE IF missing(pf_elow) THEN DO; /* ǰһ�������ޣ�ֻ��������Ϊ�Ƚϱ�׼*/
				IF gro_n >= pf_eup THEN is_improve = 1;
				ELSE is_improve = 0;
			END;
			ELSE IF missing(pf_eup) THEN DO; /* ǰһ�������� */
				IF gro_n < pf_elow THEN is_improve = -1;
				ELSE is_improve = 0;
			END;	
		END;
	END;
	ELSE is_improve = 3; 
RUN;



/** appendix:Ŀ����Ϊ�������˳�ʱ�� **/
/** Step3-appendix1: ���䣬��δ��������������ĲƱ�����*/

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

/** ��Ϊ����һ�ֿ����ǣ�ͬһ�췢����ͬ�ڵĲƱ�������������������������¼ */
PROC SQL;
	CREATE TABLE earning_actual_merge AS
	SELECT *
	FROM tmp
	GROUP BY primary_key 
	HAVING next_a_report_period = max(next_a_report_period)
	ORDER BY primary_key;
QUIT;

/** Step3-appendix2: ���䣬��δ���������������ҵ��Ԥ��ʱ��*/
/** �����report_periodû��Ҫ����Ϊ������ʲôʱ�ڷ�����ҵ���¼����䶼Ӧ��Ϊ�˳��źŴ��� */
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
	HAVING  next_f_report_period = min(next_f_report_period)   /** ѡ��������� */
	)
	GROUP BY primary_key
	HAVING next_key = min(next_key)  /* ֻ��Ϊ�˱�֤һ��һ�Ĺ�ϵ��û���κ�ɸѡҪ�� */
	ORDER BY primary_key;
QUIT;

PROC SQL;
	DROP TABLE tmp, earning_forecast_raw, earning_actual_raw, earning_actual;
QUIT;


