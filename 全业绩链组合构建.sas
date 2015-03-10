

%LET index_code = 000300;
%LET env_start_date = 20dec2005;
/* ������ */
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

 

/** Ϊ���Ż�Ч�ʣ���ȡ�����ӱ� */
 DATA hqinfo benchmark_hqinfo;
        SET hq.hqinfo(keep = end_date stock_code close factor type open high low pre_close vol istrade);
        date = datepart(end_date);
        FORMAT date mmddyy10.;
       	price = close * factor;
        IF price <= 0 THEN price = .;
        IF type = 'A' AND end_date >= "15dec2005"d THEN OUTPUT hqinfo;
        ELSE IF type = 'S' AND stock_code = "&index_code" AND end_date >= "15dec2005"d THEN OUTPUT benchmark_hqinfo;
RUN;

/* ��ҵ����� */
DATA sector_hqinfo;
	SET test.fg_index_dailyreturn;
	IF indexcode = "&index_code." AND sectortype = "һ����ҵ" AND datepart(datadate)>= "&env_start_date."d;  /* 000905: CSI500, 000906:800һ����ҵ*/
RUN;

/* ��Ȩ��ҵָ�� */
DATA sector_hqinfo(DROP =  datadate);;
	SET sector_hqinfo(keep =  datadate sectorcode weightedreturn close);
	date = datepart(datadate);
	weightedreturn = weightedreturn * 100;
	FORMAT date mmddyy10.;
	RENAME sectorcode = stock_code weightedreturn = ret close = price;
RUN;

PROC SORT DATA =  sector_hqinfo;
	BY stock_code date;
RUN;

/* ����->��ҵӳ��� */
DATA  fg_wind_sector;
	SET bk.fg_wind_sector(keep = end_date stock_code o_code o_name);
	IF datepart(end_date)>= "&env_start_date."d - 40; /* ��ǰ�������1���� */
	date = datepart(end_date);
	FORMAT date mmddyy10.;
RUN; 

/* ʱ��û����������ȫʱ�� */
PROC SQL;
	CREATE TABLE stock_list_from_sector AS
	SELECT DISTINCT stock_code
	FROM fg_wind_sector;
QUIT;

PROC SQL;
	CREATE TABLE stock_sector_mapping AS
	SELECT stock_code, date 
	FROM stock_list_from_sector, busday;
QUIT;

PROC SQL;
	CREATE TABLE tmp AS
	SELECT stock_code, date, max(base_date) FORMAT mmddyy10. AS base_date
	FROM
	(SELECT A.*, datepart(B.end_date) FORMAT mmddyy10. AS base_date FROM stock_sector_mapping A LEFT JOIN fg_wind_sector B
	ON A.stock_code = B.stock_code AND A.date >= datepart(B.end_date))  /* ����date�ĺ�����: ��һ����Ч����ҵ���� */
	GROUP BY stock_code, date;
QUIT;

PROC SQL;
	CREATE TABLE stock_sector_mapping AS
	SELECT A.stock_code, A.date, o_code, o_name
	FROM tmp A
	LEFT JOIN fg_wind_sector B
	ON A.stock_code = B.stock_code AND A.base_date = datepart(B.end_date)
	WHERE not missing(base_date)
	ORDER BY A.date, A.stock_code;
QUIT;



/*PROC SQL;*/
/*	CREATE TABLE tmp AS*/
/*	SELECT A.*, B.o_code, B.o_name*/
/*	FROM stock_sector_mapping  A LEFT JOIN fg_wind_sector B*/
/*	ON A.date = B.date AND A.stock_code = B.stock_code*/
/*	ORDER BY A.stock_code, A.date;*/
/*QUIT;*/
/**/
/*DATA stock_sector_mapping(drop =  o_code o_name rename = (o_code_2 = o_code o_name_2 = o_name));*/
/*	SET tmp;*/
/*	LENGTH o_code_2 $ 16;*/
/*	LENGTH o_name_2 $ 16;*/
/*	BY stock_code;*/
/*	RETAIN o_code_2 '';*/
/*	RETAIN o_name_2 '';*/
/*	IF first.stock_code THEN DO;*/
/*		o_code_2 = '';*/
/*		o_name_2 = '';*/
/*	END;*/
/*	IF NOT missing(o_code) THEN DO;*/
/*		o_code_2 = o_code;*/
/*		o_name_2 = o_name;*/
/*	END;*/
/*RUN;*/


/* ����һ��: ����ҵ������ָ���е�Ȩ��(sector_weight) */
/*PROC SQL;*/
/*	CREATE TABLE tmp AS*/
/*	SELECT A.*, B.sectorweight AS sector_weight*/
/*	FROM stock_sector_mapping A LEFT JOIN test.fg_index_dailyreturn B*/
/*	ON A.date = datepart(B.datadate) AND A.o_code = B.sectorcode AND indexcode = "&index_code."*/
/*	ORDER BY A.stock_code, A.date;*/
/*QUIT;*/
/**/
/*DATA  stock_sector_mapping;*/
/*	SET tmp;*/
/*RUN;*/



/* ����A�� */
PROC SQL;
	CREATE TABLE a_stock_list AS
	SELECT distinct stock_code
	FROM hq.hqinfo
	WHERE type = "A"
	ORDER BY stock_code;
QUIT;

/* �ų�δ���й�Ʊ */
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

/* ������� */
DATA stock_info_table(drop = F17_1090 F18_1090);
	SET stock_info_table;
	list_date = input(F17_1090,yymmdd8.);
	delist_date = input(F18_1090,yymmdd8.);
	IF index(stock_name,'ST') THEN is_st = 1;
	ELSE is_st = 0;
	FORMAT list_date delist_date mmddyy10.;
RUN;




/* ��ͣ���еĹ�Ʊ */
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
PROC SORT DATA = tmp;
	BY stock_code descending end_date;
RUN;

/* ��������ǰһ�������ձ� */
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


/****** ����ȫҵ����Ʊ�� **/
PROC SQL;
	CREATE TABLE tmp AS
	SELECT A.*, B.date
	FROM a_stock_list A, busday B
	WHERE "01jan2007"d <= date
	ORDER BY stock_code, date;
QUIT;

/** ɾ��δ���л����м�¼ **/

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
	IF NOT missing(delist_date) AND date > delist_date THEN delete; /* ������ */
	IF NOT missing(list_date) AND date < list_date THEN delete; /* δ���� */
	IF missing(list_date) THEN delete; /* ��δ���� */
RUN;

/** ɾ����ʱ��ͣ���еĹ�Ʊ */
PROC SQL;
	CREATE TABLE tmp AS
	SELECT A.*, B.end_date, B.pre_date AS start_date
	FROM tmp2 A LEFT JOIN halt_list_stock B
	ON A.stock_code = B.stock_code
	ORDER BY A.stock_code;
QUIT;   /* ��һ����Ʊ����������ͣ���������У����ܲ����������Ӽ�¼ */
DATA tmp;
	SET tmp;
	IF start_date <=date <=end_date THEN delete; /* ��ͣ����������������(��ͷβ) */
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

/*DATA tt;*/
/*	SET merge_signal;*/
/*	year = year(date);*/
/*RUN;*/
/*PROC SQL;*/
/*	CREATe TABLE stat AS*/
/*	SELECT year, tar_cmp, signal, count(1) AS nobs*/
/*	FROM tt*/
/*	GROUP BY year, tar_cmp, signal;*/
/*QUIT;*/


/* ���ֲ��ԣ�
(1) �������˳��ź�
(2) �̶���������
*/
%map_date_to_index(busday_table=busday, raw_table=merge_signal, date_col_name=date, raw_table_edit=merge_signal);
%map_date_to_index(busday_table=busday, raw_table=merge_stock_pool, date_col_name=date, raw_table_edit=merge_stock_pool);

PROC SQL;
	CREATE TABLE merge_stock_pool_2 AS
	SELECT A.*, B.signal, B.tar_cmp, B.date AS signal_date, B.date_index AS index_signal_date
	FROM merge_stock_pool A LEFT JOIN merge_signal B
	ON A.stock_code = B.stock_code AND A.date = B.date
	ORDER BY A.stock_code, A.date;
QUIT;

DATA merge_stock_pool_2(drop= r_hold r_hold2 r_signal_date r_index_signal_date dif_day);
	SET merge_stock_pool_2;
	BY stock_code;
	RETAIN r_hold 0;
	RETAIN r_signal_date .;
	RETAIN r_index_signal_date .;
	RETAIN r_hold2 0;  /* ���е��� */
	IF first.stock_code THEN DO;
		r_hold = 0;
		r_hold2 = 0;
		r_signal_date = .;
		r_index_signal_date = .;
	END;
	
	/** ��һ�ֲ��ԣ����е������ź� */
	hold = r_hold;  /* ��������źŹ�����������ź� */
	/* ����������ź� */
	IF tar_cmp = 1 AND signal = 1 THEN r_hold = 1;  /* �����źŷ���������һ�������տ��̺����� */
	ELSE IF tar_cmp = 1 AND signal = 0 THEN r_hold = 0;
	ELSE IF tar_cmp = 0 AND signal = 0 THEN r_hold = 0;  /* tar_cmp = 0 and signal = 1 �źŲ��� */
	
	/* �ڶ��ֲ��ԣ����й̶����� */
	hold2 = r_hold2;
	IF tar_cmp = 1 AND signal = 1 THEN DO;
		r_hold2 = 1;
		r_signal_date = signal_date;
		r_index_signal_date = index_signal_date;
	END;
	ELSE DO;
		IF NOT missing(r_index_signal_date) AND date_index - r_index_signal_date < 60 THEN r_hold2 = 1;
		ELSE r_hold2 = 0;
	END;
	dif_day = date_index - r_index_signal_date;
	FORMAT r_signal_date mmddyy10.;
RUN;


/* �����޷�����/��������� */
PROC SQL;
	CREATE TABLE tmp AS
	SELECT A.*, B.close, B.open, B.pre_close, B.high, B.low, B.vol
	FROM merge_stock_pool_2 A LEFT JOIN hqinfo B
	ON A.stock_code = B.stock_code AND A.date = B.end_date
	ORDER BY A.stock_code, A.date;
QUIT;

DATA merge_stock_pool(drop = close open pre_close high low vol);
	SET tmp;
	IF date = list_date THEN not_trade = 1; /* �������գ��������� */
	IF missing(vol) OR vol = 0 THEN not_trade = 1;
	ELSE IF close = high AND close = low AND close = open AND close > pre_close THEN not_trade = 1;  /* ��ͣ */
	ELSE IF close = high AND close = low AND close = open AND close < pre_close THEN not_trade = 1; /* ��ͣ */
	ELSE not_trade = 0;
RUN;



DATA merge_stock_pool(drop = rr_hold rr_hold2 list_date delist_date start_date end_date signal_date index_signal_date);
	SET merge_stock_pool;
	BY stock_code;
	RETAIN rr_hold .;
	RETAIN rr_hold2 .;
	IF first.stock_code THEN DO;
		rr_hold = .;
		rr_hold2 = .;
	END;
	IF (rr_hold = 0 OR missing(rr_hold)) AND hold = 1 THEN DO ;   /* �״����� */
		IF not_trade = 1 THEN DO;
			f_hold = 0;  /* �޷����� */
		END;
		ELSE DO;
			f_hold = 1;
		END;
	END;
	/* ��Ҫ���� */
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
	IF last.stock_code AND date = delist_date THEN f_hold = 0; /* ����Ѿ������һ�������գ���ǡ���������գ���ǿ������ */
	rr_hold = f_hold;

	/* ���е��ڲ��� */
	IF (rr_hold2 = 0 OR missing(rr_hold2)) AND hold2 = 1 THEN DO ;   /* �״����� */
		IF not_trade = 1 THEN DO;
			f_hold2 = 0;  /* �޷����� */
		END;
		ELSE DO;
			f_hold2 = 1;
		END;
	END;
	/* ��Ҫ���� */
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
	IF last.stock_code AND date = delist_date THEN f_hold2 = 0; /* ����Ѿ������һ�������գ���ǡ���������գ���ǿ������ */
	rr_hold2 = f_hold2;
RUN;

/** ֻѡ���Ʊ���еĹ�Ʊ */
/** ѡ�����պ͵�����Ʊ����������� */
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
	IF stock_code ~= stock_code_c THEN DO;
		f_hold = 0;
		f_hold2 = 0;
	END;
RUN;


/** ���е������źų��� */
%LET output_dir = D:\Research\DATA\yjyg_link\output_date_20140827;
%LET filename = s1_I_pool_300.xls;
PROC SQL;
	CREATE TABLE all_stock_pool AS
	SELECT A.*, B.ob_object_name_1090 AS stock_name
	FROM merge_stock_pool A LEFT JOIN locwind.TB_OBJECT_1090 B
	ON A.stock_code = B.f16_1090
	WHERE f_hold = 1 AND b.f4_1090='A'
	ORDER BY A.stock_code, A.date;
QUIT;

DATA all_stock_pool;
	SET all_stock_pool(keep = stock_code stock_name date rename = (date = end_date));
	end_time = dhms(end_date,0,0, time());
	FORMAT end_date mmddyy10.;
	FORMAT end_time datetime20.;
RUN;

DATA test_stock_pool;
	SET all_stock_pool(keep = stock_code end_date stock_name rename = (end_date = date));
	weight = 1;
	is_bm = 0;
RUN;

/** Ϊ�����Ż���Ͻ��жԱȣ�����ÿ�µ���һ�� */
/* ѡȡ�³������Ϊ��������� */
DATA tt_stock;
	SET test_stock_pool;
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

/** �����߼�˳�������Ҫ�仯һ�£�Ӧ������ȷ����Ʊ�أ������滻��Ȼ���ٿ�ʼ�������� **/

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


/*DATA sur_stock(keep = stock_code date is_bm weight);*/
/*	SET score.fg_hs300_factor;*/
/*	IF sur_pre_eps > 0;*/
/*	date = datepart(end_date);*/
/*	FORMAT date mmddyy10.;*/
/*	IF "01jan2007"d <= date <= "22aug2014"d;*/
/*	is_bm = 0;*/
/*	weight = 1;*/
/*RUN;*/
/*%fill_in_index(my_library=work, stock_pool=sur_stock, busday_table=busday, start_date="01jan2007"d, */
/*		all_max_weight=1, ind_max_weight=0.05, benchmark_code=000300, edit_stock_pool=sur_stock_mdf);*/
/*DATA sur_stock_mdf;*/
/*	SET sur_stock_mdf;*/
/*	IF date <= "22aug2014"d;*/
/*RUN;*/
/**/
/*%cal_weighted_return(stock_pool=sur_stock_mdf);*/
/*%eval_pfmance();*/

/******************** ��ҵ���Բ��� ****/
/** ��cyb900��Ϊ��׼ **/

%LET env_start_date = 20dec2005;
 %LET index_code = 000906; 
%LET my_library = work;
%LET stock_sector_mapping = stock_sector_mapping;
%LET ind_max_weight = 0.05;
%LET stock_pool=test_stock_pool;
%LET start_date = "01jan2007"d;
%LET edit_stock_pool = test_stock_pool_mdf;
%LET max_within_indus = 0.2;

%LET stock_pool = test_stock_pool_mdf;
