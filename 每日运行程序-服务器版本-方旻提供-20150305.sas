%let EndDate=2015-03-02;
%let myEndDate=03Mar2015;
 
proc sql noprint;
select put(datepart(pre_date),date9.) into :myTradeDate from etf.trade_day where end_date="&myEndDate.:00:00:00"dt;
quit;
data _null_;
  end_date=input("&EndDate.",yymmdd10.);
  y=year(end_date)-2;
  start_date=input("31Dec" || put(y,4.),date9.);
  act_date=input("31Dec" || put(y-1,4.),date9.);
  call symput("myStartDate",put(start_date,date9.));
  call symput("minDate",put(end_date-150,date9.));
  if "&isToday"="0" then call symput("maxDate",put(end_date-1,date9.));
  else call symput("maxDate","01Jan2100");
  call symput("actMinDate",put(act_date,yymmddn8.));
  if "&isToday"="0" then call symput("actMaxDate",put(end_date-1,yymmddn8.));
  else call symput("actMaxDate","21000101");
  call symput("actMinDate2",put(start_date,yymmddn8.));
run;
%put "&myStartDate. &myEndDate. &minDate. &maxDate. &actMinDate. &actMinDate2.";
 
/******************************************* 模块1： 更新业绩预告数据（缺失数据用真实净利润重新计算，调整上下限等）*******************************/
/* 获取业绩预告数据 */
PROC SQL;
    CREATE TABLE earning_forecast_raw AS
    SELECT b.symbol AS stock_code label "stock_code",b.sname AS stock_name label "stock_name",a.forecastsession,a.forecastbasesession,
      a.reportdate,a.efct9,a.efct10,a.efct11,a.efct12,a.efct14,a.efct15,a.efct16,a.efct17,a.reportunit,a.efctid
    FROM gogoal.efct AS a LEFT JOIN gogoal.securitycode AS b
    ON  a.companycode = b.companycode
   WHERE b.stype='EQA' AND reportdate>= "&myStartDate.:00:00:00"dt and reportdate<="&maxDate.:00:00:00"dt order by b.symbol,a.reportdate;
QUIT;
 
DATA earning_forecast_raw;
    SET earning_forecast_raw;
    RENAME reportdate = report_date efct14 = source efct11 = earning_des
           efct9 = eup_num efct10 = eup_ratio efct12 = eup_type
           efct15 = elow_num efct16 = elow_ratio efct17 = elow_type;
    stock_code=trim(stock_code);
    period_type = substr(forecastsession,5,1);
    IF stock_name ~= "上药转换"    /*剔除权证和上药转换*/
    AND (period_type="3" or period_type="1" or period_type="4" or period_type="2")  /*数据处理：剔除单季度预测和定性描述*/
    AND not missing(efct11)
    AND (not missing(efct9) OR not missing(efct10) OR not missing(efct15) OR not missing(efct16)); /* 至少需要上下限增长率或绝对值有一个存在)*/
    period_year= input(substr(forecastsession,1,4),8.);
    period_year_o=input(substr(forecastsession,1,4),8.)-1;
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
 
/* 寻找上一期真实业绩增长率*/
PROC SQL;
    CREATE TABLE earning_actual AS
    SELECT f16_1090 AS stock_code label='stock_code',ob_object_name_1090 AS stock_name label='stock_name',f2_1854 AS report_period label='report_period',f3_1854 AS report_date_2 label='report_date_2',
       f61_1854 AS earning_n label='earning_n', f7_1854
    FROM fgwind.tb_object_1854 AS a LEFT JOIN fgwind.TB_OBJECT_1090 AS b
    ON a.F1_1854 = b.OB_REVISIONS_1090 
    WHERE b.f4_1090='A' AND a.f4_1854='合并报表'
    AND stock_code IN
    (SELECT stock_code FROM earning_forecast_raw) and a.f2_1854>="&actMinDate" and a.f2_1854<="&actMaxDate";
 
    CREATE TABLE earning_actual_merge AS
    SELECT a.*, b.report_period AS prev_report_period, b.earning_n AS earning_o,
       round((a.earning_n - b.earning_n)/abs(b.earning_n)*100, 0.01) AS gro_n
    FROM earning_actual AS a LEFT JOIN earning_actual AS b
    ON input(a.report_period,8.) - 10000 = input(b.report_period,8.) AND a.stock_code = b.stock_code
    where a.report_period>="&actMinDate2" ORDER BY a.stock_code, a.report_period;
QUIT;
 
/* 更改report_date格式 */
DATA earning_actual_merge;
    SET earning_actual_merge;
    stock_code=trim(stock_code);
    report_date = input(trim(left(report_date_2)),yymmdd8.);
    report_period = trim(left(report_period));
    format report_date mmddyy10.;
    /*盈利分类：1为持续亏损、2为扭亏、3为亏损、4为持续正盈利 */
    IF earning_o<=0 and earning_n<=0 THEN e_type=1;
   ELSE IF earning_o<=0 and earning_n>0 THEN e_type=2;
   ELSE IF  earning_o>0 and earning_n<0 THEN e_type=3;
    ELSE IF  earning_o>0 and earning_n>0 THEN e_type=4;
RUN;
 
/* 匹配业绩预告中前一个公告期的真实业绩增长率，以计算更为准确的增长上下限 */
PROC SQL;
    CREATE TABLE tmp AS
    SELECT A.*,b.earning_n, b.e_type, b.gro_n
    FROM earning_forecast_raw a LEFT JOIN earning_actual_merge b
    ON a.stock_code = b.stock_code AND a.report_period_o = b.report_period;
QUIT;
 
DATA  earning_forecast_raw ;
    SET tmp;
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
    IF NOT MISSING(eup_ratio) THEN eup_ratio_f=eup_ratio;
    ELSE DO;
     eup_ratio_f=eup_ratio_c;  
      is_up_original = 0;
    END;
   /*    IF eup_ratio =0 and eup_num>0 THEN DO;
     eup_ratio_f=eup_ratio_c;  
      is_up_original = 0;
    END; */
 
   /*定义最后的增长率-下限*/
   IF NOT MISSING(elow_ratio) THEN elow_ratio_f=elow_ratio;
   ELSE DO;
     elow_ratio_f=elow_ratio_c;
      is_low_original = 0;
   END;
/*   IF elow_ratio =0 and elow_num>0 THEN DO;
     elow_ratio_f=elow_ratio_c;
      is_low_original = 0;  
   END;   */
 
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
 
    /*定义不同预测类型：1为期初利润小于0，2为期初利润大于0但上限和下限无意义，3为期初利润大于0，上下限有意义 */
   IF earning_n <= 0 THEN f_type = 1;
   ELSE IF missing(eup) AND missing(elow) THEN f_type = 2;
   ELSE f_type = 3;
 
  /* 保留需要的字段 */
   KEEP efctid stock_code stock_name report_date report_period source earning_des
      eup_type eup elow_type elow e_type f_type is_up_original is_low_original;
RUN;
 
 
 
 
/*********************************** 模块1结束 ***************************************************/
 
 
/************************************** 模块2： 选取当前考虑的时间周期的子样本 *****************************/
/* 取当期考虑的时间范围 */
DATA earning_forecast_ch;
    SET earning_forecast_raw;
    IF "&minDate"d <= datepart(report_date) <= "&maxDate"d;
RUN;
 
 
/* 针对个股，有多条记录：首先选最近公告期 */
/* 然后选最近公布日*/
/* 最后是来源：临时公告>年报>三季度报>半季报>一季报 */
/* 特例：即时一季度报早于去年年报公布，则仍以一季报影响占优 */
PROC SORT DATA =  earning_forecast_ch;
    BY stock_code descending report_period descending report_date descending source;
RUN;
 
DATA earning_forecast_ch;
    SET earning_forecast_ch;
    BY stock_code;
    IF first.stock_code;
RUN;
 
 
/* 寻找最近的真实业绩公告期(有可能，真实公告已经出了) */
/* 特例：若现在公布半年报数据，而历史已公布数据中：A去年年报滞后于当年一季度报，则仍选取一季报结果*/
PROC SQL;
    CREATE TABLE tmp AS
    SELECT A.*, B.report_period AS a_report_period, B.report_date AS a_report_date,
           B.gro_n AS a_gro_n, B.e_type AS a_e_type, B.earning_n AS a_earning_n
    FROM earning_forecast_ch A LEFT JOIN earning_actual_merge B
    ON A.stock_code = B.stock_code AND A.report_period >= B.report_period  /** !!! 批注(2015-03-11): 这里的问题是，如果未来期的财报数据已出。则无法准确的判定is_pub信号。历史上有3个outlier。2个是业绩预告的年份有错 */
    ORDER BY A.efctid, B.report_period desc, B.report_date desc;
QUIT;
/* 选取最近一期（或者当期)的真实业绩公告结果*/
DATA earning_forecast_ch;
    SET tmp;
    BY efctid;
    IF first.efctid;
RUN;
 
/* 寻找最近一期的业绩预告结果*/
/* 特例：若现在公布半年报数据，而历史已公布数据中：A的去年年报预告滞后于当年一季度报预告，则仍选取一季报预告结果*/
/* 最近一期业绩预告有多条公布记录，优先序：公布时间>临时公告>3季度报>半年报>1季度报 */
PROC SQL;
    CREATE TABLE tmp AS
    SELECT A.*, B.efctid AS prev_efctid, B.report_date AS prev_report_date, B.report_period AS prev_report_period,
       B.source AS prev_source, B.earning_des AS prev_earning_des,
       B.eup_type AS prev_eup_type, B.eup AS prev_eup, B.elow_type AS prev_elow_type, B.elow AS prev_elow,
       B.e_type AS prev_e_type, B.f_type AS prev_f_type,
       B.is_up_original AS prev_is_up_original, B.is_low_original AS prev_is_low_original
    FROM earning_forecast_ch A LEFT JOIN earning_forecast_raw B
    ON A.stock_code = B.stock_code AND A.report_period > B.report_period
    ORDER BY A.efctid, B.report_period desc, B.report_date desc, B.source desc;
QUIT;
DATA earning_forecast_ch;
    SET tmp;
    BY efctid;
    IF first.efctid;
RUN;
 
 
/* 事件信号说明*/
/* f_type: 1-期初利润小于0, 2-期初利润大于0, 且上下限都缺失，3-期初利润大于0，上下限有意义*/
/* a_e_type: 1- 上期持续亏损，2-上期扭亏，3-上期持续亏损，4-上期持续盈利 */
/* 注意：只有在a_e_type = 4的情况下，a_gro_n的计算才是准确且有意义的 */
/*       只有在f_type = 3的情况下，eup和elow才有意义  */
/* 两个条件都可以保证：期初利润为正 */
 
DATA earning_forecast_ch;
    SET earning_forecast_ch;
    /* 是否当期真实业绩公告已经出了 */
    IF input(report_period,8.) = input(a_report_period, 8.) THEN is_pub = 1;
    ELSE is_pub = 0;
    /*选择比较基准*/
    IF input(prev_report_period,8.) <= input(a_report_period,8.) THEN choose = 1; /* 选择真实业绩公告结果 */
    ELSE choose = 0; /* 选择业绩预告*/
    /* 相隔时间超过1年，比较效果失效*/
    IF input(report_period,8.)-max(input(prev_report_period, 8.), input(a_report_period,8.))>10000 THEN
       is_valid = 0;
    ELSE is_valid = 1;   
RUN;
 
/* 当期真实公告未出 + 比较基准有效 + 上下限至少一个有意义*/
DATA earning_forecast_ch;
    SET earning_forecast_ch;
    IF is_pub = 0 AND is_valid = 1 AND f_type = 3;
    IF (choose = 1 AND a_e_type = 4) OR (choose = 0 AND prev_f_type = 3); /* 比较基准需要各自有效 */
RUN;
 
DATA earning_forecast_ch;
    SET earning_forecast_ch;
    d_eup = eup - a_gro_n;
    d_elow = elow - a_gro_n;
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
           is_improve = 0;
       END;
    END;
    ELSE DO; /*上一期预告*/
      IF NOT MISSING(eup) AND NOT MISSING(elow) AND NOT MISSING(prev_eup) AND NOT MISSING(prev_elow) THEN DO;
           IF elow >= prev_eup THEN is_improve = 1;
           ELSE IF eup <= prev_elow THEN is_improve = -1;
           ELSE is_improve = 0;
       END;
       ELSE IF NOT MISSING(eup) AND NOT MISSING(elow) AND NOT MISSING(prev_eup) THEN DO;
           IF elow >= prev_eup THEN is_improve = 1;
           ELSE is_improve = 0;
       END;
       ELSE IF NOT MISSING(eup) AND NOT MISSING(elow) AND NOT MISSING(prev_elow) THEN DO;
           IF eup <= prev_elow THEN is_improve = -1;
           ELSE is_improve = 0;
       END;  
       ELSE IF NOT MISSING(elow) AND NOT MISSING(prev_eup) AND NOT MISSING(prev_elow) THEN DO;
           IF elow >= prev_eup THEN is_improve = 1;
           ELSE is_improve = 0;
       END;
       ELSE IF NOT MISSING(eup) AND NOT MISSING(prev_eup) AND NOT MISSING(prev_elow) THEN DO;
           IF eup <= prev_elow THEN is_improve = -1;
           ELSE is_improve = 0;
       END;
       ELSE is_improve = 2; /* no many uncertainty */
    END;
RUN;
 
/* 生成最后的股票池 */
DATA stock_pool;
    SET earning_forecast_ch;
    IF (is_improve = 1 OR is_improve = 0) AND eup_type = "预增";  /* 条件 */
    KEEP efctid report_date report_period stock_code stock_name sur;
    if eup ne . and elow ne . then sur=sum(eup,elow)/2;
    else if eup ne . then sur=eup;
    else sur=elow;
RUN;
 
PROC SORT DATA = stock_pool;
    BY report_period report_date;
RUN;
 
