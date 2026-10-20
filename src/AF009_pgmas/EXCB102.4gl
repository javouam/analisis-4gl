###############################################################################
#Propietario   => SURA                                                        #
#Programa      => EXCB102                                                     #
# Febrero 2011 => DEVOLUCION DE PAGOS EN EXCESO CARGA Y PROVISION. rq19435_PJF#
###############################################################################
# Diciembre 2014 => Cambiar diagnostico PENDIENTE por Rechazos, omitir siefore#
#                   5 notificar en detalle 08 del archivo de envio solo cuando#
#                   existan rechazos. RQ21718_PJF                             #
###############################################################################
# Diciembre 2015 => Integrar funcion fn_precio_dia y validar siefore por      #
#                   catalogo tc_siefore_local. RQ25372_PJF                    #
###############################################################################
# Modifico       => Ma. Eugenia Figueroa Hernandez.                           #
#                => Req 43365 Devolucion Pagos en Exceso   19/06/2019         #
#                => Se Elimina Registro 08 de carga Archivo   TDF             # 
###############################################################################
DATABASE safre_af
GLOBALS
  DEFINE gparam_dev  RECORD    LIKE seg_modulo.*,
         ghoy                  DATE,
         gusuario              CHAR(08),
         ghora_max             CHAR(08),
         g_bat       RECORD    LIKE dis_ctrl_proceso.*,
         gfolio                INTEGER, 
         gcla_sel              CHAR(500),
         generar               CHAR(25),
         gtipo_reporte         CHAR(01),
         greg        RECORD
           nss                 CHAR(11),
           clave_ent_orig      CHAR(03),
           consec_reg_lote     INTEGER,
           folio_pago_sua      CHAR(6),          
           periodo_pago        CHAR(6),
           monto_ret           DECIMAL(16,6), #ID-16 IMPORTE RETIRO A DEVOLVER
           monto_act_ret       DECIMAL(16,6), #ID-20 ACT. Y RECARGOS
           imp_rnd_ret_indv    DECIMAL(16,6), #ID-25 RNDIMIENTOS EN CTA INDIV
           monto_cv_pat        DECIMAL(16,6), #ID-17 CV (CTA PATRÓN)
           monto_act_cv_pat    DECIMAL(16,6), #ID-21 ACT. Y RECARGOS CV PAT
           imp_rnd_cv_indv_pat DECIMAL(16,6), #ID-26 ACT. CV RENDI. INDIV PAT
           monto_cuo_soc       DECIMAL(16,6), #ID-19 CUOTA SOCIAL A DEVOLVER 
           monto_apor_pat_viv  DECIMAL(16,6), #ID-22 APORTA. PATRONAL DE VIV.
           num_viv_aport_pat   DECIMAL(20,6)  #ID-24 NÚM.APLI.VIV.APORT.PAT
         END RECORD,
         gmarca_entra          SMALLINT,
         gsiefore              SMALLINT,
         g_sol_imss   ARRAY[999] OF RECORD   
           rech_diag           INTEGER,              
           rech_impt           DECIMAL(16,2) 
         END RECORD,
         g_sol_info   ARRAY[999] OF RECORD 
           rech_diag           INTEGER,
           rech_impt           DECIMAL(16,2) 
         END RECORD,
         g_soltot              INTEGER,
         g_sol001              INTEGER,
         g_sol001_acep         INTEGER,
         g_sol001_rej          INTEGER,
         g_sol001_par          INTEGER,
         g_sol002              INTEGER,
         g_sol002_acep         INTEGER,
         g_sol002_rej          INTEGER,
         g_sol002_par          INTEGER,
         g_sol_acep            INTEGER, 
         g_sol_rej             INTEGER,
         g_sol_par             INTEGER,
         gnomb_soli            CHAR(50),
         gruta_soli            CHAR(100),
         gnomb_impo            CHAR(50),
         gruta_impo            CHAR(100),
         g_sc                  SMALLINT,
         g_accs                DECIMAL(22,6),
         g_pesos               DECIMAL(22,2),
         g_tm                  SMALLINT,
         gtotsieacep           INTEGER,
		fec_lote_08            CHAR(06),
		id1_pago_08            CHAR(16),
		id2_pago_08			   CHAR(16),
		lflote_arch            CHAR(08),
        vfecha_siefores_char  DATE,
		HOY                   DATE	
 
  ## Globales para SCA
  DEFINE r_te_cef_log          RECORD LIKE safre_seg:te_cef_log.*,
         r_sesion RECORD
             sesion            CHAR(100),
             ip_login          CHAR(15),
             usuario           CHAR(12),
             portal            INTEGER,
             privilegio        INTEGER,
             modulo            INTEGER,
             perfiles          CHAR(30),
             aplicativo        CHAR(6),
             sistema           CHAR(30)
         END RECORD,
         vch_parametro         CHAR(300),
         programa              CHAR(20),
         vch_letrero           CHAR(120),
         vch_modulo_uri        CHAR(50),
         vch_version_id        CHAR(5),
         vch_dato1             CHAR(15),
         vch_dato2             CHAR(15),
         vch_ip_login          CHAR(15),
         v_exe_fn              CHAR(300),
         vch_fecha             CHAR(20),
         vts_hora              DATETIME hour TO second,
         vin_cod_sal           INTEGER,
         vin_product_id        INTEGER,
         vin_conta             INTEGER,
         vin_priv_ini          INTEGER,
         vsm_sw                SMALLINT,
         vsm_numarg            SMALLINT,
         vsm_tip_opc           SMALLINT,
         vsm_status            SMALLINT,
         x                     SMALLINT,
         y                     SMALLINT
  ## Globales para SCA

  ## Globales para LOGS
  DEFINE v_msg_w               CHAR(80)
  DEFINE v_procedure           CHAR(300)
  DEFINE v_ret                 INTEGER
  DEFINE op                    CHAR(01)
  DEFINE key                   INTEGER
  DEFINE v_txt                 CHAR(200)
  DEFINE v_cod_err             INTEGER
  DEFINE v_today               CHAR(20)
  DEFINE v_time                DATETIME HOUR TO SECOND
  DEFINE v_window              SMALLINT
  ## Globales para LOGS

END GLOBALS
#*********************************************************************

GLOBALS   "EXCB136.4gl"    #Programa que realiza validacion de importes

MAIN

   -- OPTIONS 
   -- INPUT WRAP,
   -- PROMPT LINE LAST,
   -- ACCEPT KEY CONTROL-I
   -- DEFER INTERRUPT

  CALL STARTLOG("/safre/exc/logs/EXCB102.log")
  WHENEVER ERROR CALL graba_logs_err

  CALL Sca_Valida(1)

  CALL Sca_Valida(2)

  CALL inicio()
  CALL Proceso()
  CALL envia_mail()
  
  LET vch_letrero = "Programa : ",
                    r_sesion.privilegio using "<<<<&",
                    " - ", programa clipped,
                    "  finaliza correctamente "

  CALL Graba_Log('2002', '1', vch_letrero, " ", " ", TRUE)

END MAIN
#*********************************************************************

FUNCTION inicio()
  DEFINE lsiefore SMALLINT,
         lprecio  DECIMAL(19,6),
         li       SMALLINT

  SELECT *, USER INTO gparam_dev.*, gusuario
    FROM seg_modulo
   WHERE modulo_cod = "exc"

  LET ghoy   = TODAY

END FUNCTION

FUNCTION Proceso()
  DEFINE lresultado   CHAR(50)

  LET gcla_sel = NULL
  LET gcla_sel = " SELECT MAX(hora_inicial) ",
                 " FROM   dis_ctrl_proceso ",
                 " WHERE  fecha_proceso = ","'",ghoy,"'",
                 " AND    proceso_cod = 'EXC' ",
                 " AND    etapa_cod = 1 " CLIPPED

  PREPARE claexe FROM gcla_sel

  LET ghora_max = NULL
  DECLARE cur_proceso CURSOR FOR claexe
  OPEN cur_proceso
    FETCH cur_proceso INTO ghora_max
  CLOSE cur_proceso

  LET gcla_sel = NULL
  LET gcla_sel = " SELECT * ",
                 " FROM   dis_ctrl_proceso ",
                 " WHERE  fecha_proceso = ","'",ghoy,"'",
                 " AND    proceso_cod = 'EXC' ",
                 " AND    etapa_cod = 1 ",       
                 " AND    hora_inicial = ","'",ghora_max,"'" CLIPPED

  PREPARE claexe2 FROM gcla_sel

  DECLARE cur_proceso2 CURSOR FOR claexe2

  OPEN cur_proceso2
    FETCH cur_proceso2 INTO g_bat.*
  CLOSE cur_proceso2

  LET generar = g_bat.parametro1 CLIPPED

  IF generar IS NOT NULL THEN
     CALL Proceso_principal()

     IF gfolio = 0 THEN
        LET lresultado = "ESTE ARCHIVO YA HA SIDO PROCESADO"
     ELSE 

       CALL cif_con()                                           

       LET lresultado = 'A:',g_sol_acep   USING "#,###,##&",
                        ' R:',g_sol_rej   USING "#,###,##&",
                        ' PA:',g_sol_par  USING "#,###,##&"
     END IF

     CALL Actualiza_etapa(1,lresultado)
  END IF

  DISPLAY "PROCESO TERMINADO DE PAGOS EN EXCESO"

END FUNCTION
#*********************************************************************

FUNCTION Proceso_principal()
  DEFINE lresultado   CHAR(50)

  CALL Inicializa()
    LET HOY = TODAY 
  	SELECT catva_descorta      --- tdf 
	INTO   vfecha_siefores_char
	FROM   safre_ing:tc_cat_catalogo  
	WHERE  appin_id    = 8
	AND    agrsm_clave = 7
	AND    catsm_clave = 1

  DISPLAY "Fecha Cambio Siefores ", vfecha_siefores_char
  DISPLAY "Fecha hoy", HOY   
  ---  LET vfecha_siefores_char = HOY solo pruebas 
  DISPLAY "PROCESANDO INFORMACION..."

  CALL Ingresa_etapa(2,"Inicia separa archivo de pagos en exceso") 
  CALL Separa_archivo()                                  -- ETAPA 2
  CALL Actualiza_etapa(2,"Termina separa archivo de pagos en exceso")
  CALL Ingresa_etapa(3,"Inicia carga historicos de pagos en exceso")
  CALL Sube_datos()         -- ETAPA 3

  DISPLAY 'FOLIO GENERADO :',  gfolio 

  CALL Actualiza_etapa_1(1)
  CALL Actualiza_etapa_1(2)
  CALL actualiza_monto()
  CALL Actualiza_etapa(3,"Termina carga historicos de pagos en exceso")

  CALL Ingresa_etapa(4,"Inicia diagnostico de devoluacion por importe")
  CALL validacion(gfolio)                                -- ETAPA 4
  CALL Actualiza_etapa(4,"Termina diagnostico de devolucion por importe")

END FUNCTION
#*********************************************************************

FUNCTION Inicializa()

  LET gfolio     = 0

END FUNCTION
#*********************************************************************

FUNCTION Ingresa_etapa(vetapa_cod,vresultado)
  DEFINE vetapa_cod     DECIMAL(2,0),
         vresultado     CHAR(50),
         lhora_inicial  CHAR(08),
         lhora_final    CHAR(08)

  LET lhora_inicial = TIME
  LET lhora_final   = NULL

  INSERT INTO dis_ctrl_proceso
       VALUES (TODAY,             -- fecha_proceso
               "EXC",             -- proceso_cod
               vetapa_cod,        -- etapa_cod   
               lhora_inicial,      -- hora_inicial
               lhora_final,        -- hora_final
               g_bat.parametro1,  -- parametro1
               NULL,              -- parametro2
               NULL,              -- parametro3
               NULL,              -- parametro4
               NULL,              -- parametro5
               gfolio,            -- folio 
               vresultado,        -- resultado
               gusuario           -- usuario
              )

  UPDATE dis_ctrl_proceso SET parametro4 = ghoy 
                        WHERE parametro1 = g_bat.parametro1
                          AND etapa_cod  = 1
                          AND folio      = gfolio

  IF SQLCA.SQLCODE <> 0 THEN
     DISPLAY "ERROR  AL INSERTAR EN TABLA dis_ctrl_proceso etapa ",
             vetapa_cod," ",STATUS

     EXIT PROGRAM
  END IF

END FUNCTION
#*********************************************************************

FUNCTION Separa_archivo()  -- ETAPA 2 
  DEFINE lejecuta        CHAR(300)

  DISPLAY "SEPARANDO ARCHIVO,ETAPA 2"

  LET lejecuta = "sed -e '/^01/!d' ",gparam_dev.ruta_rescate CLIPPED,"/",
                 generar CLIPPED," >",gparam_dev.ruta_rescate CLIPPED,
                 "/excdev_cza"
  RUN lejecuta

  LET lejecuta = "sed -e '/^02/!d' ",gparam_dev.ruta_rescate CLIPPED,"/",
                 generar CLIPPED," >",gparam_dev.ruta_rescate CLIPPED,
                 "/excdev_det"
  RUN lejecuta
  
   IF  vfecha_siefores_char >  HOY THEN
       DISPLAY "CARGA REGISTRO 08"

       LET lejecuta = "sed -e '/^08/!d' ",gparam_dev.ruta_rescate CLIPPED,"/",
                 generar CLIPPED," >",gparam_dev.ruta_rescate CLIPPED,
                 "/excdev_dep"
       RUN lejecuta
    ELSE
	  DISPLAY " NO CARHA REGISTRO 08"
	  LET lejecuta = " touch ",gparam_dev.ruta_rescate CLIPPED, "/excdev_dep"
      RUN lejecuta
  END IF

  LET lejecuta = "sed -e '/^09/!d' ",gparam_dev.ruta_rescate CLIPPED,"/",
                 generar CLIPPED," >",gparam_dev.ruta_rescate CLIPPED,
                 "/excdev_sum"
  RUN lejecuta

  DISPLAY "SEPARACION DE ARCHIVO TERMINADO,ETAPA 2"

END FUNCTION
#*********************************************************************

FUNCTION Actualiza_etapa(letapa_cod,lresultado)
  DEFINE letapa_cod   DECIMAL(2,0),
         lresultado   CHAR(50),
         lhora_final  CHAR(08)

  LET gcla_sel = NULL
  LET gcla_sel = " SELECT MAX(hora_inicial) ",
                 " FROM   dis_ctrl_proceso ",
                 " WHERE  fecha_proceso = ","'",ghoy,"'",
                 " AND    proceso_cod = 'EXC' ",
                 " AND    etapa_cod = ",letapa_cod

  PREPARE claexe3 FROM gcla_sel

  DECLARE cur_proceso3 CURSOR FOR claexe3

  LET ghora_max = NULL
  OPEN cur_proceso3
    FETCH cur_proceso3 INTO ghora_max
  CLOSE cur_proceso3

  LET lhora_final   = TIME

  LET gcla_sel = " UPDATE dis_ctrl_proceso ",
                 " SET    hora_final = ","'",lhora_final,"',",
                 "        folio      = ",gfolio,",",
                 "        resultado  = ","'",lresultado,"'",
                 " WHERE  fecha_proceso = ","'",ghoy,"'",
                 " AND    proceso_cod   = 'EXC'",
                 " AND    etapa_cod     = ",letapa_cod,
                 " AND    hora_inicial  = ","'",ghora_max,"'" CLIPPED
  PREPARE claexe4 FROM gcla_sel

  EXECUTE claexe4

END FUNCTION
#*********************************************************************

FUNCTION Actualiza_etapa_1(vetapa_cod)
  DEFINE vetapa_cod   DECIMAL(2,0)

  LET gcla_sel = NULL
  LET gcla_sel = " SELECT MAX(hora_inicial) ",
                 " FROM   dis_ctrl_proceso ",
                 " WHERE  fecha_proceso = ","'",ghoy,"'",
                 " AND    proceso_cod = 'EXC' ",
                 " AND    etapa_cod = ",vetapa_cod

  LET ghora_max  = NULL 
  PREPARE claexe5 FROM gcla_sel
  DECLARE cur_proceso5 CURSOR FOR claexe5
  OPEN cur_proceso5
    FETCH cur_proceso5 INTO ghora_max
  CLOSE cur_proceso5

  LET gcla_sel = NULL
  LET gcla_sel = " UPDATE dis_ctrl_proceso ",
                 " SET    folio      = ",gfolio,
                 " WHERE  fecha_proceso = ","'",ghoy,"'",
                 " AND    proceso_cod   = 'EXC'",
                 " AND    etapa_cod     = ",vetapa_cod,
                 " AND    hora_inicial  = ","'",ghora_max,"'" CLIPPED

  PREPARE claexe6 FROM gcla_sel

  EXECUTE claexe6

END FUNCTION
#*********************************************************************

FUNCTION Sube_datos()  -- ETAPA 3
  DEFINE lejecuta         CHAR(300),
         lid_pago         CHAR(16),
         lfecha_lote      CHAR(10),
         lflote_arch      CHAR(08),    
         l_lote           CHAR(03),
         lfecha_aux       DATE,
         lfecha_recepcion DATE,
         lhora_recepcion  CHAR(10),
         lestado          SMALLINT,
         lfecha_estado    DATE,
         lhora_estado     CHAR(10),
         lreporte         CHAR(300),
         ldisplay_id      CHAR(50),
         lcontenido       CHAR(1),
         lposicion1       CHAR(1),
         lposicion2       CHAR(1)

  DISPLAY "SUBE DATOS A TABLAS HISTORICAS,ETAPA 3"

  LET lejecuta = "cd ",gparam_dev.ruta_rescate CLIPPED,
                 "; cut -c 17-24 excdev_cza > excdev_fecha_lote"
  RUN lejecuta

  LET lejecuta = "cd ",gparam_dev.ruta_rescate CLIPPED,
                 "; cut -c 25-27 excdev_cza > excdev_lote"
  RUN lejecuta
 
  LET lejecuta = "cd ",gparam_dev.ruta_rescate CLIPPED,
                 "; cut -c 28-35 excdev_cza > excdev_fecha_liq"
  RUN lejecuta

  LET lejecuta = "cd ",gparam_dev.ruta_rescate CLIPPED,
                 "; cut -c 5-20 excdev_dep > excdev_id_pago"
  RUN lejecuta

  WHENEVER ERROR CONTINUE
    DROP TABLE fec_dev_lote
    DROP TABLE lote_dev
    DROP TABLE fec_dev_liq
    DROP TABLE id_pago_dev
  WHENEVER ERROR STOP

  CREATE TEMP TABLE fec_dev_lote
    (fecha_lote CHAR(08))

  CREATE TEMP TABLE lote_dev
    (lote CHAR(03))
    
  CREATE TEMP TABLE fec_dev_liq
    (fecha_liquida CHAR(08))

  CREATE TEMP TABLE id_pago_dev
    (id_pago CHAR(16))


  LET lejecuta = gparam_dev.ruta_rescate CLIPPED,
                "/excdev_fecha_liq" CLIPPED
 
  LOAD FROM lejecuta INSERT INTO fec_dev_liq
  
  LET lejecuta = gparam_dev.ruta_rescate CLIPPED,
                "/excdev_fecha_lote" CLIPPED

  LOAD FROM lejecuta INSERT INTO fec_dev_lote

  LET lejecuta = gparam_dev.ruta_rescate CLIPPED,
                "/excdev_lote" CLIPPED

  LOAD FROM lejecuta INSERT INTO lote_dev

  LET lejecuta = gparam_dev.ruta_rescate CLIPPED,
                "/excdev_id_pago" CLIPPED

  LOAD FROM lejecuta INSERT INTO id_pago_dev

  
  IF  vfecha_siefores_char >  HOY THEN  --TDF
  
  DECLARE cur_idpago CURSOR FOR
  SELECT id_pago
    FROM id_pago_dev
  FOREACH cur_idpago INTO lid_pago

    LET lposicion1 = lid_pago[13]

    IF lposicion1 <> "3" THEN
       LET ldisplay_id = "Proceso cancelado <ENTIDAD A DEVOLVER> invalida: ",
                         lposicion1
						 
        DISPLAY "Proceso cancelado <ENTIDAD A DEVOLVER> invalida: ", lposicion1
						 
       CALL Actualiza_etapa(3,ldisplay_id)

       EXIT PROGRAM
    END IF

    LET lposicion2 = lid_pago[14]

    IF  lposicion2 = "7" OR lposicion2 = "8" THEN
    ELSE
       LET ldisplay_id = "Proceso cancelado <TIPO DE DEPOSITO> invalida: ",
                         lposicion2
       DISPLAY  "Proceso cancelado <TIPO DE DEPOSITO> invalida: ", lposicion2
       CALL Actualiza_etapa(3,ldisplay_id)

       EXIT PROGRAM
    END IF
   END FOREACH
 END IF
  SELECT fecha_lote INTO lflote_arch 
    FROM fec_dev_lote

  SELECT lote INTO l_lote
    FROM lote_dev 

  LET lfecha_lote = lflote_arch[5,6],"/",
                    lflote_arch[7,8],"/",
                    lflote_arch[1,4]

  LET lfecha_aux = lfecha_lote   

  SELECT "X"
    FROM exc_cza_exceso
   WHERE fecha_creac_lote = lfecha_aux
     AND consecutivo_dia  = l_lote

  IF SQLCA.SQLCODE <> 0 THEN

     INSERT INTO glo_folio
          VALUES (0)

     SELECT MAX(folio) INTO gfolio
       FROM glo_folio

     LET lfecha_recepcion = TODAY
     LET lhora_recepcion  = TIME
     LET lestado          = 2
     LET lfecha_estado    = TODAY
     LET lhora_estado     = TIME

     --------------------   GENERA exc_cza_exceso   --------------------

     LET lreporte = gparam_dev.ruta_rescate CLIPPED,"/dev_fol_cza"

     START REPORT salida TO lreporte

     LET gtipo_reporte = "C"   ---- Cabeza

     OUTPUT TO REPORT salida(lfecha_recepcion,
                             lhora_recepcion,
                             lestado,
                             lfecha_estado,
                             lhora_estado)
     FINISH REPORT salida

     LET lejecuta = "cd ",gparam_dev.ruta_rescate CLIPPED,
                   "; paste dev_fol_cza excdev_cza > dev_cza1" CLIPPED
     RUN lejecuta

     LET lejecuta = "cd ",gparam_dev.ruta_rescate CLIPPED,
                   "/;sed 's/	//g' dev_cza1 > exc_cza "
     RUN lejecuta

     LET lejecuta = "cd ",gparam_dev.ruta_exp CLIPPED,
                   "/;DBDATE=y4md;export DBDATE;dbload -d safre_af ",
                   "-c sube_exceso_cza -l /tmp/",
                   gusuario CLIPPED,".dbload_exc_cza.log -e 1 -k;"
     RUN lejecuta


     --------------------   GENERA adi   --------------------

     LET lreporte = gparam_dev.ruta_rescate CLIPPED,"/dev_adi"

     START REPORT salida2 TO lreporte
       LET lcontenido = "a"

       OUTPUT TO REPORT salida2(lcontenido)
     FINISH REPORT salida2

     --------------------   GENERA exc_det_devpgo   --------------------


     LET lreporte = gparam_dev.ruta_rescate CLIPPED,"/dev_fol_cza1"

     START REPORT salida1 TO lreporte

       LET gtipo_reporte = "D"   ---- Detalle

       OUTPUT TO REPORT salida1(lestado,
                                lfecha_estado,
                                lhora_estado)
     FINISH REPORT salida1

     -- Se crea archivo adi que contiene a\  y se pega en dev_fol_det

     LET lejecuta = "cd ",gparam_dev.ruta_rescate CLIPPED,
                   "; cat dev_adi dev_fol_cza1 > dev_fol_det" CLIPPED

     RUN lejecuta

     -- Se crea archivo dev_fol_det2 con el numero de registros igual al
     -- num. registros que tiene el detalle

     LET lejecuta = "cd ",gparam_dev.ruta_rescate CLIPPED,
                    "; sed -f dev_fol_det excdev_det > dev_fol_det2" CLIPPED
     RUN lejecuta

     -- Se crea archivo dev_fol_det borrando lineas que no sirven

     LET lejecuta = "cd ",gparam_dev.ruta_rescate CLIPPED,
                   "; sed -e '/^ /!d' dev_fol_det2 > dev_fol_det" CLIPPED 
     RUN lejecuta

     -- Se crea dev_det1 pegando datos genrales con el detalle 

     LET lejecuta = "cd ",gparam_dev.ruta_rescate CLIPPED,
                   "; paste dev_fol_det excdev_det > dev_det1" CLIPPED
     RUN lejecuta


     -- Se crea det eliminando espacio en blanco que se genera cuando
     -- se pegan los 2 archivos

     LET lejecuta = "cd ",gparam_dev.ruta_rescate CLIPPED,
                   "/;sed 's/	//g' dev_det1 > excdev_det "
     RUN lejecuta

     -- Se suben los datos del detalle

     LET lejecuta = "cd ",gparam_dev.ruta_exp CLIPPED,
                   "/;DBDATE=y4md;export DBDATE;dbload -d safre_af -c ",
                   "sube_excdev_det -l /tmp/",gusuario CLIPPED,
                   ".dbload_excdev_det.log -e 1 -k;"
     RUN lejecuta

     --------------------   GENERA exc_dep_devpgo   --------------------

     -- Se crea archivo adi que contiene a\  y se pega en dev_fol_dep

     LET lejecuta = "cd ",gparam_dev.ruta_rescate CLIPPED,
                   "; cat dev_adi dev_fol_cza1 > dev_fol_dep" CLIPPED
     RUN lejecuta


     -- Se crea archivo dev_fol_dep2 con el numero de registros igual al
     -- num. registros que tiene el detalle

     LET lejecuta = "cd ",gparam_dev.ruta_rescate CLIPPED,
                   "; sed -f dev_fol_dep excdev_dep > dev_fol_dep2" CLIPPED
     RUN lejecuta

     -- Se crea archivo dev_fol_det borrando lineas que no sirven

     LET lejecuta = "cd ",gparam_dev.ruta_rescate CLIPPED,
                   "; sed -e '/^ /!d' dev_fol_dep2 > dev_fol_dep" CLIPPED 
     RUN lejecuta

     -- Se crea dev_dep1 pegando datos genrales con el detalle 

     LET lejecuta = "cd ",gparam_dev.ruta_rescate CLIPPED,
                   "; paste dev_fol_dep excdev_dep > dev_dep1" CLIPPED
     RUN lejecuta

     -- Se crea det eliminando espacio en blanco que se genera cuando
     -- se pegan los 2 archivos

     LET lejecuta = "cd ",gparam_dev.ruta_rescate CLIPPED,
                   "/;sed 's/	//g' dev_dep1 > excdev_dep "
     RUN lejecuta

     -- Se suben los datos del detalle

     IF  vfecha_siefores_char >  HOY THEN
     LET lejecuta = "cd ",gparam_dev.ruta_exp CLIPPED,
                   "/;DBDATE=y4md;export DBDATE;dbload -d safre_af -c ",
                   "sube_excdev_dep -l /tmp/",gusuario CLIPPED,
                   ".dbload_excdev_dep.log -e 1 -k;"
     RUN lejecuta
     END IF
     --------------------   GENERA exc_sum_exceso   --------------------

     LET lejecuta = "cd ",gparam_dev.ruta_rescate CLIPPED,
                   "; paste dev_fol_cza1 excdev_sum > dev_sum1" CLIPPED
     RUN lejecuta

     LET lejecuta = "cd ",gparam_dev.ruta_rescate CLIPPED,
                   "/;sed 's/	//g' dev_sum1 > excdev_sum "
     RUN lejecuta

     LET lejecuta = "cd ",gparam_dev.ruta_exp CLIPPED,
                   "/;DBDATE=y4md;export DBDATE;dbload -d safre_af -c ",
                   "sube_excdev_sum -l /tmp/",gusuario CLIPPED,
                   ".dbload_excdev_sum.log -e 1 -k;"
     RUN lejecuta

     -- Se borran todo los archivo auxiliares
      LET lejecuta = "cd ",gparam_dev.ruta_rescate CLIPPED,
                    "; rm archivos exc_cza excdev_det excdev_dep excdev_sum ",
                    "excdev_fecha_lote excdev_id_pago excdev_lote dev_fol_cza ",
                    "dev_fol_cza1 dev_fol_dep dev_fol_dep2 dev_fol_det ",
                    "dev_fol_det2 dev_cza1 dev_det1 dev_dep1 dev_sum1 dev_adi"
     RUN lejecuta   

     LET lejecuta = "cd ",gparam_dev.ruta_exp CLIPPED,
                   "/;DBDATE=mdy4;export DBDATE;"

     RUN lejecuta

   IF  vfecha_siefores_char <= HOY THEN
      DISPLAY " GENERA ID PAGO REGISTRO 08 "
      CALL ins_reg_08(gfolio,lflote_arch)  
   END IF 
  ELSE
     DISPLAY "ESTE ARCHIVO YA HA SIDO PROCESADO"
     LET gfolio = 0
  END IF

  DISPLAY "SUBE DATOS A TABLAS HISTORICAS TERMINADO,ETAPA 3"

END FUNCTION

 FUNCTION ins_reg_08(gfolio,lflote_arch)
 
 DEFINE lflote_arch   CHAR(08)
 DEFINE gfolio        INTEGER
 DEFINE hora_inserta  CHAR(08)
 DEFINE w_fecLiq        CHAR(08)
 DEFINE fecLiq     CHAR(10)
 
 LET  hora_inserta = TIME
 LET id1_pago_08 = ' '  
 LET id2_pago_08 = ' '
 LET fec_lote_08 = lflote_arch[3,8]
 
  
 SELECT fecha_liquida INTO w_fecLiq
    FROM fec_dev_liq
	

 LET fecliq = w_fecLiq[5,6],"/",w_fecLiq[7,8],"/",w_fecLiq[1,4]	
 
 
 
 LET  id1_pago_08 = '01544', fec_lote_08 , '13711'
 LET  id2_pago_08 = '01544', fec_lote_08 , '13732'

 INSERT INTO safre_af:exc_dep_devpgo 
 VALUES (gfolio,2,ghoy,hora_inserta , '08','03',id1_pago_08,0,fecliq,0,0,0,0,0,0,0,0,0,0,' ',0)
 INSERT INTO safre_af:exc_dep_devpgo 
 VALUES (gfolio,2,ghoy, hora_inserta , '08','03',id2_pago_08,0,fecliq,0,0,0,0,0,0,0,0,0,0,' ',0)
 IF SQLCA.SQLCODE <> 0 THEN
     DISPLAY " ERROR al insertar registros en exc_dep_devpgo  "
 END IF

 
END FUNCTION 

FUNCTION actualiza_monto()
  DEFINE ldet           RECORD
           monto_ret           DECIMAL(16,6),
           monto_cv_pat        DECIMAL(16,6),
           monto_cv_tra        DECIMAL(16,6),
           monto_cuo_soc       DECIMAL(16,6),
           monto_act_ret       DECIMAL(16,6),
           monto_act_cv_pat    DECIMAL(16,6),
           monto_act_cv_tra    DECIMAL(16,6),           
           monto_apor_pat_viv  DECIMAL(16,6),
           num_viv_aport_pat   DECIMAL(24,6),
           imp_rnd_ret_indv    DECIMAL(16,6),
           imp_rnd_cv_indv_pat DECIMAL(16,6),
           imp_rnd_cv_indv_tra DECIMAL(16,6)
         END RECORD,
         ldep           RECORD
           ident_pago         CHAR(16),
           monto_soli_institu DECIMAL(28,6),
           imp_acep_rcv_adev  DECIMAL(28,6),
           imp_pend_rcv       DECIMAL(28,6),
           imp_rchz_rcv       DECIMAL(28,6),
           num_aiv_solic      DECIMAL(30,6),
           num_aiv_acep       DECIMAL(30,6),
           num_aiv_pend       DECIMAL(30,6),
           num_aiv_rchz       DECIMAL(30,6),
           imp_viv_acep_adev  DECIMAL(28,6),
           imp_viv_pend       DECIMAL(28,6),
           imp_viv_rchz       DECIMAL(28,6),          
           codigo_siefore     SMALLINT
         END RECORD,
         lsum           RECORD
           monto_tot_rcv      DECIMAL(28,6),
           monto_tot_pat_viv  DECIMAL(28,6),
           monto_tot_gub      DECIMAL(28,6),
           monto_tot_par_viv  DECIMAL(32,6)
         END RECORD

  DECLARE cursor_2 CURSOR FOR
  SELECT NVL(monto_ret,0),
         NVL(monto_cv_pat,0),
         NVL(monto_cv_tra,0),
         NVL(monto_cuo_soc,0),
         NVL(monto_act_ret,0),
         NVL(monto_act_cv_pat,0),
         NVL(monto_act_cv_tra,0),
         NVL(monto_apor_pat_viv,0),
         NVL(num_viv_aport_pat,0),
         NVL(imp_rnd_ret_indv,0),
         NVL(imp_rnd_cv_indv_pat,0),
         NVL(imp_rnd_cv_indv_tra,0)
    FROM exc_det_devpgo 
   WHERE folio = gfolio
  FOR UPDATE
  FOREACH cursor_2 INTO ldet.monto_ret,
                        ldet.monto_cv_pat,
                        ldet.monto_cv_tra,
                        ldet.monto_cuo_soc,
                        ldet.monto_act_ret,
                        ldet.monto_act_cv_pat,
                        ldet.monto_act_cv_tra,           
                        ldet.monto_apor_pat_viv,
                        ldet.num_viv_aport_pat

    UPDATE exc_det_devpgo 
       SET monto_ret           = ldet.monto_ret/100,
           monto_cv_pat        = ldet.monto_cv_pat/100,
           monto_cv_tra        = ldet.monto_cv_tra/100,
           monto_cuo_soc       = ldet.monto_cuo_soc/100,
           monto_act_ret       = ldet.monto_act_ret/100,
           monto_act_cv_pat    = ldet.monto_act_cv_pat/100,
           monto_act_cv_tra    = ldet.monto_act_cv_tra/100,
           monto_apor_pat_viv  = ldet.monto_apor_pat_viv/100,
           num_viv_aport_pat   = ldet.num_viv_aport_pat/1000000,
           imp_rnd_ret_indv    = imp_rnd_ret_indv/100,
           imp_rnd_cv_indv_pat = imp_rnd_cv_indv_pat/100,
           imp_rnd_cv_indv_tra = imp_rnd_cv_indv_tra/100          
     WHERE CURRENT OF cursor_2

  END FOREACH

  DECLARE cursor_3 CURSOR FOR
  SELECT ident_pago[14,15],
         NVL(monto_soli_institu,0),
         NVL(imp_acep_rcv_adev,0),
         NVL(imp_pend_rcv,0),
         NVL(imp_rchz_rcv,0),
         NVL(num_aiv_solic,0),
         NVL(num_aiv_acep,0),
         NVL(num_aiv_pend,0),
         NVL(num_aiv_rchz,0),
         NVL(imp_viv_acep_adev,0),
         NVL(imp_viv_pend,0),
         NVL(imp_viv_rchz,0),
         codigo_siefore
    FROM exc_dep_devpgo 
   WHERE folio = gfolio
  FOR UPDATE 
  FOREACH cursor_3 INTO ldep.ident_pago,
                        ldep.monto_soli_institu,
                        ldep.imp_acep_rcv_adev,
                        ldep.imp_pend_rcv,
                        ldep.imp_rchz_rcv,
                        ldep.num_aiv_solic,
                        ldep.num_aiv_acep,
                        ldep.num_aiv_pend,
                        ldep.num_aiv_rchz,
                        ldep.imp_viv_acep_adev,
                        ldep.imp_viv_pend,
                        ldep.imp_viv_rchz,          
                        ldep.codigo_siefore

    LET ldep.codigo_siefore = 0

    UPDATE exc_dep_devpgo
       SET monto_soli_institu = ldep.monto_soli_institu/100,
           imp_acep_rcv_adev  = ldep.imp_acep_rcv_adev/100,
           imp_pend_rcv       = ldep.imp_pend_rcv/100,
           imp_rchz_rcv       = ldep.imp_rchz_rcv/100,
           num_aiv_solic      = ldep.num_aiv_solic/1000000,
           num_aiv_acep       = ldep.num_aiv_acep/1000000,
           num_aiv_pend       = ldep.num_aiv_pend/1000000,
           num_aiv_rchz       = ldep.num_aiv_rchz/1000000,
           imp_viv_acep_adev  = ldep.imp_viv_acep_adev/100,
           imp_viv_pend       = ldep.imp_viv_pend/100,
           imp_viv_rchz       = ldep.imp_viv_rchz/100, 
           codigo_siefore     = ldep.codigo_siefore 
     WHERE CURRENT OF cursor_3

  END FOREACH

  DECLARE cursor_4 CURSOR FOR
  SELECT NVL(monto_tot_rcv,0),
         NVL(monto_tot_pat_viv,0),
         NVL(monto_tot_gub,0),
         NVL(num_tot_par_viv,0)
    FROM exc_sum_devpgo
   WHERE folio = gfolio
  FOR UPDATE
  FOREACH cursor_4 INTO lsum.monto_tot_rcv,
                        lsum.monto_tot_pat_viv,
                        lsum.monto_tot_gub,
                        lsum.monto_tot_par_viv

    UPDATE exc_sum_devpgo
       SET monto_tot_rcv     = lsum.monto_tot_rcv/100,
           monto_tot_pat_viv = lsum.monto_tot_pat_viv/100,
           monto_tot_gub     = lsum.monto_tot_gub/100,
           num_tot_par_viv = lsum.monto_tot_par_viv/1000000
     WHERE CURRENT OF cursor_4

  END FOREACH

END FUNCTION
#*********************************************************************

REPORT salida(rfecha_recepcion,
              rhora_recepcion,
              restado,
              rfecha_estado,
              rhora_estado)

  DEFINE rfecha_recepcion DATE,
         rhora_recepcion  CHAR(08),
         restado          CHAR(01),
         rfecha_estado    DATE,
         rhora_estado     CHAR(08)

  OUTPUT
    TOP MARGIN 0
    LEFT MARGIN 0
    BOTTOM MARGIN 0
    PAGE LENGTH 1

  FORMAT
    ON EVERY ROW
      IF gtipo_reporte = "C" THEN
         PRINT gfolio           USING '----------',
               rfecha_recepcion USING "YYYY/MM/DD",
               rhora_recepcion,
               restado,
               rfecha_estado    USING "YYYY/MM/DD",
               rhora_estado 
      ELSE
         PRINT gfolio           USING '----------'
      END IF

END REPORT
#*********************************************************************

REPORT salida1(restado,
               rfecha_estado,
               rhora_estado)
  DEFINE restado          CHAR(01),
         rfecha_estado    DATE,
         rhora_estado     CHAR(08)

  OUTPUT
    TOP    MARGIN 0
    LEFT   MARGIN 0
    BOTTOM MARGIN 0
    PAGE   LENGTH 1

  FORMAT
    ON EVERY ROW
      IF gtipo_reporte = "D" THEN
         PRINT gfolio        USING '----------',
               restado,
               rfecha_estado USING "YYYY/MM/DD",
               rhora_estado 
      ELSE
         PRINT gfolio        USING '----------'
      END IF

END REPORT
#*********************************************************************
REPORT salida2(vcontenido)
  DEFINE vcontenido    CHAR(1)

  OUTPUT
    TOP MARGIN 0
    LEFT MARGIN 0
    BOTTOM MARGIN 0
    PAGE LENGTH 1

  FORMAT
    ON EVERY ROW
      PRINT vcontenido, "\\"
END REPORT
#*********************************************************************

FUNCTION cif_con()
  DEFINE lreg  RECORD
           cve_ent_orig CHAR(03),
           diag         CHAR(02),
           rsult_ope    SMALLINT,
           total        INTEGER,
           imp_imss     DECIMAL(16,2),
           imp_infov    DECIMAL(16,2)
         END RECORD,
         li             SMALLINT,
         lrsult_ope     SMALLINT,
         lsiefore_ant   SMALLINT,
         lsemafo_sie    SMALLINT,
         lejecuta       CHAR(500) 

  LET gnomb_soli = "excb002_cc"
  LET gruta_soli = gparam_dev.ruta_rescate CLIPPED,"/",gnomb_soli CLIPPED,
                   ".txt"

  START REPORT r_report TO gruta_soli

  FOR li = 1 TO 999
    LET g_sol_imss[li].rech_diag   = 0
    LET g_sol_imss[li].rech_impt   = 0
    LET g_sol_info[li].rech_diag   = 0
    LET g_sol_info[li].rech_impt   = 0
  END FOR

  SELECT COUNT(*) INTO g_soltot              # solicitudes procesadas
    FROM exc_det_devpgo
   WHERE folio = gfolio
     
  SELECT COUNT(*) INTO g_sol001             # solicitudes imss
    FROM exc_det_devpgo
   WHERE folio = gfolio
     AND clave_ent_orig = '001'

  SELECT COUNT(*) INTO g_sol002              # solicitudes infonavit
    FROM exc_det_devpgo
   WHERE folio = gfolio
     AND clave_ent_orig = '002'

  SELECT COUNT(*) INTO g_sol001_acep         # solicitudes imss acep
    FROM exc_det_devpgo
   WHERE folio = gfolio
     AND clave_ent_orig  = '001'
     AND diag_devolucion = '01'               
   
  SELECT COUNT(*) INTO g_sol001_rej         # solicitudes imss recha
    FROM exc_det_devpgo
   WHERE folio = gfolio
     AND clave_ent_orig  = '001'
     AND diag_devolucion = '02'               

  SELECT COUNT(*) INTO   g_sol001_par       # solicitudes imss parciales 
    FROM exc_det_devpgo
   WHERE folio = gfolio
     AND clave_ent_orig   = '001'
     AND diag_devolucion  = '04'               

  #solicitudes imss rechazadas por diagnostico
  DECLARE cc_001_02 CURSOR FOR                    
  SELECT clave_ent_orig, diag_devolucion, motivo_devolucion, COUNT(*),          
         SUM(monto_ret        +
             monto_act_ret    +
             imp_rnd_ret_indv +
             monto_cv_pat     +
             monto_act_cv_pat +
             monto_act_cv_pat +
             monto_cuo_soc),                            #Total imp IMSS 
         SUM(monto_apor_pat_viv)                        #Total imp INFONAVIT
    FROM exc_det_devpgo
   WHERE folio           = gfolio 
     AND diag_devolucion = '02'
  GROUP BY clave_ent_orig, diag_devolucion, motivo_devolucion 
  ORDER BY clave_ent_orig, diag_devolucion, motivo_devolucion
  FOREACH  cc_001_02 INTO lreg.cve_ent_orig, 
                          lreg.diag,
                          lreg.rsult_ope,
                          lreg.total,
                          lreg.imp_imss,
                          lreg.imp_infov 

    LET lrsult_ope = lreg.rsult_ope 

    IF lreg.cve_ent_orig = '001' THEN   #Solicitudes dev pagos IMSS 

       IF lreg.diag = '02' THEN    #Rechazadas
          LET g_sol_imss[lrsult_ope].rech_diag = lreg.total 
          LET g_sol_imss[lrsult_ope].rech_impt = lreg.imp_imss 
       END IF

    END IF

    IF lreg.cve_ent_orig = '002' THEN   #Solicitudes dev pagos INFONAVIT

       IF lreg.diag = '02' THEN    #Rechazadas
          LET g_sol_info[lrsult_ope].rech_diag = lreg.total 
          LET g_sol_info[lrsult_ope].rech_impt = lreg.imp_infov 
       END IF

    END IF
   
  END FOREACH

  SELECT COUNT(*) INTO g_sol002_acep       # solicitudes infonavit acep
    FROM exc_det_devpgo
   WHERE folio = gfolio
     AND clave_ent_orig   = '002'
     AND diag_devolucion  = '01'               
   
  SELECT COUNT(*) INTO g_sol002_rej        # solicitudes infonavit recha
    FROM exc_det_devpgo
   WHERE folio = gfolio
     AND clave_ent_orig   = '002'
     AND diag_devolucion  = '02'               

  SELECT COUNT(*) INTO g_sol002_par        # solicitudes infonavit parciales
    FROM exc_det_devpgo
   WHERE folio = gfolio
     AND clave_ent_orig   = '002'
     AND diag_devolucion  = '04'               

  LET g_sol_acep = g_sol001_acep + g_sol002_acep
  LET g_sol_rej  = g_sol001_rej  + g_sol002_rej 
  LET g_sol_par  = g_sol001_par  + g_sol002_par 

  OUTPUT TO REPORT r_report()
  FINISH REPORT r_report


  LET gnomb_impo = "excb2_cp_cza"
  LET gruta_impo = gparam_dev.ruta_rescate CLIPPED,"/",gnomb_impo CLIPPED,
                   ".txt"
  START REPORT p_report_cza TO gruta_impo
    OUTPUT TO REPORT p_report_cza() --- Los precios se obtien  de EXCB136
  FINISH REPORT p_report_cza

  LET gnomb_impo = "excb2_cp_det"
  LET gruta_impo = gparam_dev.ruta_rescate CLIPPED,"/",gnomb_impo CLIPPED,
                   ".txt"
  START REPORT p_report_det TO gruta_impo
  LET lsiefore_ant = NULL
  LET lsemafo_sie  = 0 
  LET gtotsieacep  = 0 

  DECLARE dp_001 CURSOR FOR
  SELECT siefore, 
         subcuenta,
         SUM(imp_dis_accion), 
         SUM(imp_dis_pesos),
         tipo_movimiento
    FROM safre_tmp:exc_devpgo_sdo
   WHERE folio         = gfolio
     AND diagnostico IN (1,4)
     AND imp_dis_pesos > 0
  GROUP BY 1,2,5
  ORDER BY 1,2,5
  FOREACH dp_001 INTO gsiefore,
                      g_sc,
                      g_accs,
                      g_pesos,
                      g_tm 

    IF lsiefore_ant IS NULL THEN 
       LET lsemafo_sie  = 1
    ELSE
       IF lsiefore_ant <> gsiefore THEN
          LET lsemafo_sie = 1
       END IF
    END IF
    
    IF lsemafo_sie = 1 THEN 
       
       SELECT COUNT(UNIQUE nss) INTO gtotsieacep
         FROM safre_tmp:exc_devpgo_sdo
        WHERE folio         = gfolio
          AND siefore       = gsiefore
          AND diagnostico  IN (1,4)
          AND imp_dis_pesos > 0  
    
    END IF

    OUTPUT TO REPORT p_report_det()

    LET lsemafo_sie  = 0
    LET lsiefore_ant = gsiefore
    LET gtotsieacep  = 0 

  END FOREACH 

  FINISH REPORT p_report_det

  LET gnomb_impo = "excb002_cp"
  LET lejecuta = " cat ",gparam_dev.ruta_rescate CLIPPED,"/excb2_cp_cza.txt ",
                         gparam_dev.ruta_rescate CLIPPED,"/excb2_cp_det.txt > ",
                         gparam_dev.ruta_rescate CLIPPED,"/",
                         gnomb_impo CLIPPED,".txt " 
  RUN lejecuta

END FUNCTION

REPORT r_report()
  DEFINE ri SMALLINT

  OUTPUT
    PAGE LENGTH  90
    LEFT MARGIN  0
    RIGHT MARGIN 160
    TOP   MARGIN 0
    BOTTOM MARGIN 0

  FORMAT
    PAGE HEADER
      PRINT COLUMN   1, 'EXCB102',
            COLUMN  12, '        SURA AFORE',
            COLUMN  50, TODAY  USING "DD/MM/YYYY",
            COLUMN  65, 'PAGINA',
            COLUMN  72, PAGENO USING "#####"
      PRINT COLUMN  05, 'CIFRAS DEVOLUCION DE PAGOS SIN JUSTIFICACION LEGAL',
                        '(CARGA DE ARCHIVO)'
      PRINT COLUMN  05, 'FOLIO : ',gfolio USING "#########"
      PRINT

    ON EVERY  ROW
      PRINT
      PRINT COLUMN  01, "Solicitudes recibidas....",
            COLUMN  30, g_soltot USING "###,###,##&"

      PRINT COLUMN  01, "    IMSS.................",
            COLUMN  30, g_sol001 USING "###,###,##&"

      PRINT COLUMN  01, "    INFONAVIT...........",
            COLUMN  30, g_sol002 USING "###,###,##&"
      PRINT

      PRINT COLUMN  01, "Solicitudes aceptadas....",
            COLUMN  30, g_sol_acep USING "###,###,##&"
      PRINT COLUMN  01, "    IMSS.................",
            COLUMN  30, g_sol001_acep USING "###,###,##&"
      PRINT COLUMN  01, "    INFONAVIT...........",
            COLUMN  30, g_sol002_acep USING "###,###,##&"
      PRINT

      PRINT COLUMN  01, "Solicitudes rechazadas...",
            COLUMN  30, g_sol_rej  USING "###,###,##&"
      PRINT COLUMN  01, "    IMSS.................",
            COLUMN  30, g_sol001_rej  USING "###,###,##&"
      PRINT COLUMN  01, "    INFONAVIT...........",
            COLUMN  30, g_sol002_rej  USING "###,###,##&"
      PRINT

      PRINT COLUMN  01, "Solicitudes parciales ...",
            COLUMN  30, g_sol_par  USING "###,###,##&"
      PRINT COLUMN  01, "    IMSS.................",
            COLUMN  30, g_sol001_par  USING "###,###,##&"
      PRINT COLUMN  01, "    INFONAVIT...........",
            COLUMN  30, g_sol002_par  USING "###,###,##&"
      PRINT

      PRINT COLUMN  01, "Solicitudes IMSS rechazadas por diagnostico"
      PRINT COLUMN 001, "Diagnostico",
            COLUMN 020, "Cantidad",
            COLUMN 040, "Importe"

      FOR ri=1 TO 999
        IF g_sol_imss[ri].rech_diag > 0 THEN
           PRINT COLUMN 001, ri     using "&&&",
                 COLUMN 004,"...............",
                 COLUMN 020, g_sol_imss[ri].rech_diag using "###,###,##&",
                 COLUMN 040, g_sol_imss[ri].rech_impt using "#,###,##&.&&"
        END IF
      END FOR
      PRINT

      PRINT COLUMN  01, "Solicitudes INFONAVIT rechazadas por diagnostico"
      PRINT COLUMN 001, "Diagnostico",
            COLUMN 020, "Cantidad",
            COLUMN 040, "Importe"

      FOR ri=1 TO 999
        IF g_sol_info[ri].rech_diag > 0 THEN
           PRINT COLUMN 001, ri     using "&&&",
                 COLUMN 004,"...............",
                 COLUMN 020, g_sol_info[ri].rech_diag using "###,###,##&",
                 COLUMN 040, g_sol_info[ri].rech_impt using "#,###,##&.&&" 
        END IF
      END FOR

END REPORT

REPORT p_report_cza()
  DEFINE ri    SMALLINT

  OUTPUT
    PAGE   LENGTH   4
    LEFT   MARGIN   0
    RIGHT  MARGIN   0
    TOP    MARGIN   0
    BOTTOM MARGIN   0

  FORMAT
    ON EVERY  ROW
      FOR ri = 1 TO gtot_arr_prec
        IF ri =  1 THEN
           PRINT COLUMN  1,  'EXCB102',
                 COLUMN  12, '        SURA AFORE',
                 COLUMN  50, TODAY  USING "DD/MM/YYYY",
                 COLUMN  65, 'PAGINA',
                 COLUMN  72, PAGENO USING "#####"
           PRINT COLUMN  05, 'CIFRAS DEVOLUCION DE PAGOS SIN JUSTIFICACION',
                             ' LEGAL'
           PRINT COLUMN 005, 'Importes Calculados del FOLIO : ', 
                             gfolio USING "#########"
        END IF

        IF garr_prec[ri].siefore <> 0 THEN
           PRINT COLUMN 030, "Precio S",
                             garr_prec[ri].siefore USING "##&","  ", 
                             garr_prec[ri].precio  USING "#&.######"
        END IF
      END FOR

END REPORT


REPORT p_report_det()

  OUTPUT
    PAGE   LENGTH  90
    LEFT   MARGIN   0
    RIGHT  MARGIN 160
    TOP    MARGIN   0
    BOTTOM MARGIN   0

  FORMAT
    PAGE HEADER

      PRINT COLUMN 030, 'Fecha conversion ', ghoy
      PRINT
      PRINT COLUMN 001, "SIEFORE",
            COLUMN 009, "SUBCTA",
            COLUMN 016, "T.MOVTO",
            COLUMN 024, "TOT_NSS",
            COLUMN 033, "   TITULOS   ",
            COLUMN 053, "    PESOS    "
      PRINT

    ON EVERY  ROW
      PRINT COLUMN 001, gsiefore     USING "###&",
            COLUMN 011, g_sc         USING "#&" ,
            COLUMN 018, g_tm         USING "###",
            COLUMN 024, gtotsieacep  USING "###,###",
            COLUMN 033, g_accs       USING "###,###,##&.&&&&&&", 
            COLUMN 053, g_pesos      USING "$$$,$$$,$$&.&&" 

END REPORT

FUNCTION  envia_mail()
  DEFINE lcadena_mail CHAR(550),
         lejecuta     CHAR(250)
  
  LET lejecuta = "sh /safre/est/shells/env_mail_gral.sh ",
                 "Informe/de/solicitudes/dev/pago ",
                 gnomb_soli CLIPPED," ","txt"," ",
                 gparam_dev.ruta_rescate CLIPPED," ",
                 programa CLIPPED
                  
  RUN lejecuta

  LET lejecuta = "sh /safre/est/shells/env_mail_gral.sh ",
                 "Informe/de/importes/dev/pago ",
                 gnomb_impo CLIPPED," ","txt"," ",
                 gparam_dev.ruta_rescate CLIPPED," ",
                 programa CLIPPED

  RUN lejecuta

END FUNCTION 
    
#Sca_Valida     Funcion que realiza las validaciones para SCA.  Puede
#               recibir 2 valores en el parametro 'origen':
#               1 = carga lo parametros iniciales en el programa que
#                   sirven para el SCA.  Registra en tabla LOG
#               2 = realiza las validaciones (de sesion, de privilegio, de 
#                   perfiles) cada vez que el usuario interactua en el programa
FUNCTION Sca_Valida(origen)
DEFINE
    origen         SMALLINT,
    vsm_sw1        SMALLINT,
    vsm_sw2        SMALLINT,
    vin_modulo     INTEGER,
    vch_sesion     CHAR(100)

    DATABASE safre_seg

    CASE origen 
       WHEN 1 
         LET programa = ARG_VAL(0)
         LET vsm_numarg = NUM_ARGS()
         LET r_sesion.modulo = ARG_VAL(vsm_numarg)
         LET vch_sesion = ARG_VAL(vsm_numarg - 1)
         LET r_sesion.sesion = vch_sesion
         LET vch_fecha = TODAY using "mmm dd yyyy"
         LET vts_hora = CURRENT
         LET v_window = TRUE
         LET vin_priv_ini = 3732  ---EXCB102   1796 --EXCB001
         LET r_sesion.privilegio = vin_priv_ini
         LET vch_version_id = '0'
         LET vin_product_id = 9 --AF-009

         LET v_exe_fn = 'EXECUTE PROCEDURE Carga_Parametros_sca(?,?,?,?,?,?,?) '
         PREPARE sp_cargaparam FROM v_exe_fn
         EXECUTE sp_cargaparam USING vch_sesion, 
                                     programa, 
                                     vin_product_id,
                                     vch_version_id,
                                     r_sesion.privilegio,
                                     vch_fecha,
                                     vts_hora
         INTO vsm_sw1, vsm_sw2, r_sesion.ip_login, r_sesion.usuario,
              r_sesion.portal, r_sesion.perfiles, r_sesion.aplicativo,
              r_sesion.sistema, vch_letrero

         IF vsm_sw1 > 0 OR vsm_sw2 > 0 THEN
            ERROR vch_letrero
            SLEEP 4
            CALL ERRORLOG(vch_letrero)
         END IF
         IF vsm_sw1 > 0 THEN
            EXIT PROGRAM
         END IF

      WHEN 2
         LET v_exe_fn = 'EXECUTE PROCEDURE sp_sca_valida(?,?,?,?,?,?,?,?,?,?) '
         PREPARE sp_valida FROM v_exe_fn
         EXECUTE sp_valida USING programa,
                                 r_sesion.sesion,
                                 r_sesion.ip_login,
                                 r_sesion.usuario,
                                 r_sesion.portal,
                                 r_sesion.privilegio,
                                 r_sesion.modulo,
                                 r_sesion.perfiles,
                                 r_sesion.aplicativo,
                                 r_sesion.sistema
         INTO vsm_sw, vin_cod_sal, vch_letrero, vch_modulo_uri,
              vsm_tip_opc, vin_modulo
         IF vsm_sw <> 0 THEN
            ERROR vch_letrero
            SLEEP 4
            CALL ERRORLOG(vch_letrero)
            IF vin_cod_sal <> 99 THEN
               CALL Graba_Log('3001', '9', vch_letrero, " ", " ", TRUE)
            ELSE
               CALL Graba_Log('3002', '6', vch_letrero, " ", " ", TRUE)
            END IF 
            EXIT PROGRAM vin_cod_sal
         END IF

      OTHERWISE
            LET vch_letrero = 'La rutina Sca_Valida NO recibio parametros',
                              '  Fin de programa inesperado'
            CALL ERRORLOG(vch_letrero)
            EXIT PROGRAM
    END CASE
    DATABASE safre_af

END FUNCTION

#####################################################################
#- Funcion que trata los errores generados en tiempo de ejecucion
#- 1. Graba en el archivo .LOG del programa
#- 2. Graba en la tabla de LOG de informix (te_cef_log)
#- 3. Despliega en pantalla ventana con datos del error,
#-    confirmar con <enter> para continuar
#  4. Se ha agrega WHENEVER ERROR CONTINUE para tabla te_cef_log
#  5. La ventana de ERROR no aplica para el ERROR de conexion a otra 
#     INSTANCIA (var. v_st_err_i), ni error al insert en te_cef_log
#  6. la var. v_window = TRUE muestra ventana de error y confirma usuario 
#  7. la var. v_window = FALSE NO muestra ventana de error para procesos
#     que se ejecutan automaticamente y no tiene interaccion con el usuario 
#####################################################################
FUNCTION graba_logs_err()
DEFINE v_st_err        SMALLINT
DEFINE v_st_err_i      SMALLINT
DEFINE v_des_err       CHAR(120)
DEFINE v_signature_id  CHAR(4)
DEFINE v_severity_id   CHAR(2)

   LET v_cod_err  = SQLCA.SQLCODE LET v_st_err = TRUE LET v_st_err_i = FALSE 

   IF v_cod_err = 0 THEN 
      LET v_st_err = FALSE 
   END IF

   WHENEVER ERROR CONTINUE
   DATABASE safre_seg

   IF SQLCA.SQLCODE <> 0 THEN 
      LET v_st_err_i = TRUE 
      LET v_cod_err  = SQLCA.SQLCODE 
   END IF

   LET v_today 	      = TODAY USING "mmm dd yyyy" 	  
   LET v_time         = CURRENT 	
   LET v_des_err      = ERR_GET(v_cod_err)
   LET v_signature_id = '6001'
   LET v_severity_id  = '7'

   LET v_procedure = "EXECUTE PROCEDURE sp_graba_logs_err(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?) "

   PREPARE exe_procedure FROM v_procedure
   EXECUTE exe_procedure USING v_today,v_time, r_sesion.ip_login, r_sesion.usuario, programa, v_cod_err, v_des_err, v_st_err, v_st_err_i,
                               r_te_cef_log.cefts_event, vin_product_id, r_te_cef_log.cefch_vendor, v_signature_id, v_severity_id, vch_version_id, r_te_cef_log.cefch_hostname,
                               r_te_cef_log.cefch_event_name, r_te_cef_log.cefch_extension
   INTO  v_ret,v_txt
   IF v_ret <> TRUE THEN
        CALL ERRORLOG(v_txt)
        IF NOT v_st_err_i THEN
           LET v_cod_err = v_ret
           LET v_st_err_i = TRUE	
        END IF
   END IF

   WHILE (v_window = TRUE AND v_st_err_i = FALSE AND (key <> fgl_keyval("RETURN")))
      OPEN WINDOW win_err AT 18,5 WITH 4 ROWS, 70 COLUMNS ATTRIBUTE (BORDER)
      OPTIONS PROMPT LINE LAST, MESSAGE LINE LAST

      IF v_st_err THEN
         LET v_msg_w = "Se ha producido el error: ", v_cod_err using "-<<<<<<<<", ". Por favor contacte a SISTEMAS. "
      ELSE
         LET v_msg_w = "ERROR, Verifique el archivo LOG del programa."
      END IF
      DISPLAY v_msg_w AT 2,2 ATTRIBUTE (REVERSE)
      PROMPT " Presione la tecla <ENTER> para continuar .... " FOR CHAR op
      IF (FGL_LASTKEY() = fgl_keyval("RETURN")) THEN
         EXIT WHILE
      ELSE
         MESSAGE  " !!!! ERROR, debe presionar la tecla <ENTER> !!!! "  SLEEP 3 MESSAGE ""
      END IF
      CLOSE WINDOW win_err
   END WHILE
   IF v_st_err THEN
      LET vch_letrero = "Se ha producido el error: ", v_cod_err using "-<<<<<<<<", ".  Se cierra programa "
   ELSE
       LET vch_letrero = "ERROR, Verifique el archivo LOG del programa. Se cierra programa"
   END IF

   DATABASE safre_af
   WHENEVER ERROR CALL graba_logs_err

   IF NOT v_st_err_i THEN
      CALL Graba_Log('2002', '8', vch_letrero, " ", " ", TRUE)
      EXIT PROGRAM
   END IF
END FUNCTION

FUNCTION Graba_Log(vch_signature, vch_severity, vch_letrero,
                   vch_dato1, vch_dato2, vsm_swlog)
DEFINE
   vch_signature    CHAR(4),
   vch_severity     CHAR(2),
   vch_letrero      CHAR(120),
   vch_dato1        CHAR(15),
   vch_dato2        CHAR(15),
   vsm_swlog        SMALLINT,
   x                SMALLINT

   DATABASE safre_seg

   LET vch_ip_login = r_sesion.ip_login
   LET x = 0
   LET vch_fecha = TODAY using "mmm dd yyyy"
   LET vts_hora = CURRENT
   LET v_exe_fn = 'EXECUTE PROCEDURE graba_log(?,?,?,?,?,?,?,?,?,?,?,?,?) '
   PREPARE sp_grabalog FROM v_exe_fn
   EXECUTE sp_grabalog USING vin_product_id, vch_signature, vch_severity,
                             vch_letrero, vch_dato1, vch_dato2,
                             x, vch_ip_login, programa, r_sesion.usuario,
                             vch_version_id, vch_fecha, vts_hora
   INTO vsm_swlog, vch_letrero

   IF vsm_swlog = FALSE THEN
      CALL ERRORLOG(vch_letrero)
   END IF

   DATABASE safre_af

END FUNCTION
