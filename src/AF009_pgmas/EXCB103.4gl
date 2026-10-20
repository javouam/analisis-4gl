#*****************************************************************************#
#Propietario       => SURA                                                    #
#Programa          => EXCB103                                                 #
#Febrero 2011   => RESPUESTA A PROCESAR DE PAGOS EN EXCESO BATCH. RQ19435_PJF #
#*****************************************************************************#
# Diciembre 2014 => Cambiar diagnostico PENDIENTE por Rechazos, omitir siefore#
#                   5 notificar en detalle 08 del archivo de envio solo cuando#
#                   existan rechazos. RQ21718_PJF                             #
###############################################################################
# Diciembre 2015 => Integrar funcion fn_precio_dia y validar siefore por      #
#                   catalogo tc_siefore_local. RQ25372_PJF                    #
###############################################################################
#Modifico        => Ma. Eugenia Figueroa    03/07/2019                        #
#                => Req 43365 Devolucion Pagos en Exceso                      #
#                => Eliminacion Registro 08 TDF                               # 
###############################################################################

DATABASE safre_af
GLOBALS
  DEFINE g_tabafore  RECORD  LIKE tab_afore_local.*,
         gtipo_ent_origen    CHAR(02),
         g_det       RECORD  LIKE exc_det_devpgo.*,
         g_dep       RECORD 
           ident_pago          CHAR(16),
           monto_soli_institu  DECIMAL(16,6),
           fecha_liquidacion   DATE,
           imp_acep_rcv_adev   DECIMAL(16,6),
           imp_pend_rcv        DECIMAL(16,6),
           imp_rchz_rcv        DECIMAL(16,6),
           num_aiv_solic       DECIMAL(20,6),
           num_aiv_acep        DECIMAL(20,6),
           num_aiv_pend        DECIMAL(20,6),
           num_aiv_rchz        DECIMAL(20,6),
           imp_viv_acep_adev   DECIMAL(16,6),
           imp_viv_pend        DECIMAL(16,6),
           imp_viv_rchz        DECIMAL(16,6),
           siefore_desc        CHAR(08),
           codigo_siefore      SMALLINT 
         END RECORD,
         g_sum   RECORD 
           fecha_creac_lote   DATE,
           consecutivo_dia    CHAR(03),
           num_reg_aport_lote CHAR(08)
         END RECORD, 
         gfolio              INTEGER,
         g_ruta              CHAR(100),
         gusuario            CHAR(10),
         gmonto_tot_rcv      DECIMAL(16,6),
         gmonto_tot_pat_viv  DECIMAL(16,6),
         gmonto_tot_gub      DECIMAL(16,6),
         gnum_apor_acep_adev DECIMAL(06), 
         gnum_apor_rechazada DECIMAL(06),
         gnum_apor_pendiente DECIMAL(06),
         gnum_reg_pagar      INTEGER,
         gnum_tot_reg        INTEGER,
         gnum_tot_par_viv    DECIMAL(20,6),
         gsema_diagnostico   SMALLINT,
         gtitulo_reporte     CHAR(20),
         gtotsieacep         INTEGER,
		 vfecha_siefores_char  DATE,
		 HOY                   DATE,
		 lejecuta              CHAR(100),
		 regpagar              CHAR(06)
		 
  
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

GLOBALS   "EXCB136.4gl"    #Programa que realiza validacion de importes

#*********************************************************************
MAIN 


  CALL STARTLOG("/safre/exc/logs/EXCB103.log")
  WHENEVER ERROR CALL graba_logs_err
   LET HOY = TODAY
   
  CALL Sca_Valida(1)

  LET gfolio = ARG_VAL(1)

  CALL Sca_Valida(2)

  CALL inicio()
  CALL proceso()
  CALL cif_con()
  CALL envia_mail()

  LET vch_letrero = "Programa : ",
                     r_sesion.privilegio using "<<<<&",
                     " - ", programa clipped,
                     "  finaliza correctamente "
  CALL Graba_Log('2002', '1', vch_letrero, " ", " ", TRUE)

END MAIN

#*********************************************************************
FUNCTION inicio ()
  DEFINE lprecio_accion DECIMAL(22,6),
         li             SMALLINT,
         lsiefore       SMALLINT,
         lveces         INTEGER 

  ---- Verifica si folio ya se liquido
  LET gsema_diagnostico = 0     
  LET lveces = 0

  SELECT COUNT(*) INTO lveces
    FROM dis_cuenta
   WHERE folio = gfolio

  IF lveces IS NULL THEN
     LET lveces = 0
  END IF

  IF lveces >= 1 THEN
     --- Si ya se liquido solo genera el archivo ya no realiza diagnostico
     LET gsema_diagnostico = 1     
  END IF

  SELECT *, USER INTO g_tabafore.*, gusuario
     FROM tab_afore_local

  LET gtipo_ent_origen = "01"    #TIPO DE ENTIDAD ORIGEN   

  SELECT ruta_envio INTO g_ruta 
    FROM seg_modulo
   WHERE modulo_cod = "exc"

  DATABASE safre_tmp

  WHENEVER ERROR CONTINUE
    DROP TABLE exc_dep08 
  WHENEVER ERROR STOP

  CREATE TABLE exc_dep08
    ( siefore SMALLINT,
      importe DECIMAL(20,6)
    ) 
  
  DATABASE safre_af

  LET gmonto_tot_rcv      = 0
  LET gmonto_tot_gub      = 0
  LET gnum_apor_acep_adev = 0
  LET gnum_apor_rechazada = 0
  LET gnum_apor_pendiente = 0
  LET gnum_reg_pagar      = 0
  LET gnum_tot_reg        = 0

END FUNCTION

#*********************************************************************
FUNCTION proceso()
  DEFINE lresultado   CHAR(50),
         lhoy1        DATE,
         lnom_arch    CHAR(15),
         lejecuta     CHAR(500),
         lpermisos    CHAR(100)

  IF gfolio IS NOT NULL THEN

     IF gsema_diagnostico = 0 THEN
        --- Se diagnostica cuando no se ha liquidado
        CALL validacion(gfolio)
        LET gtitulo_reporte = "PREVIO"
     ELSE
        CALL ObtenerPrecios() 
        LET gtitulo_reporte = "DEFINITIVO"
     END IF

     CALL archc_ncbzdo() 
     CALL reg_02()

     ---- Elimina dep ya generados con el mismo folio estado = 3
     ---- Esto por que seran insertados nuevamente.

     DELETE FROM exc_dep_devpgo WHERE folio              = gfolio
                                  AND ident_pago[14,15] IN ("71","73") 
                                  AND estado             = 3

     CALL ctaPorCobrar08_001()
     CALL ctaPorCobrar08_002()
	SELECT catva_descorta
	INTO   vfecha_siefores_char
	FROM   safre_ing:tc_cat_catalogo
	WHERE  appin_id    = 8
	AND    agrsm_clave = 7
	AND    catsm_clave = 1

	-- LET vfecha_siefores_char = TODAY --- soli pruebas
	
	DISPLAY " Fecha Cambio Siefores  ", vfecha_siefores_char
	DISPLAY " HOY ", HOY
	  
       IF  vfecha_siefores_char >  HOY THEN
  	    DISPLAY " GENERA REGISTRO 08"
         CALL archc_dep() 
		 LET regpagar = gnum_reg_pagar USING "&&&&&&"
        ELSE
		 
	    DISPLAY " NO GENERA REGISTRO 08"
	    LET lejecuta = " touch ",g_ruta CLIPPED,"/dev_dep "
        RUN lejecuta
		LET regpagar = gnum_reg_pagar USING "######"
       END IF 
	
     CALL archc_sum()
    
     SELECT a.fecha_creac_lote INTO lhoy1
       FROM exc_cza_exceso a
      WHERE a.folio = gfolio

     LET lnom_arch = lhoy1 USING "yyyymmdd" ,".DEV" CLIPPED

     LET lejecuta = "cat ",g_ruta CLIPPED,"/dev_cza ",
                           g_ruta CLIPPED,"/dev_det ",
                           g_ruta CLIPPED,"/dev_dep ",     
                           g_ruta CLIPPED,"/dev_sum ",
                           " > ",g_ruta CLIPPED,"/",lnom_arch  CLIPPED

     RUN lejecuta

     LET lpermisos = "chmod 777 ",g_ruta CLIPPED,"/",lnom_arch CLIPPED
     RUN lpermisos

     LET lejecuta = "cd ",g_ruta CLIPPED,
                     "; rm  dev_cza dev_det dev_dep dev_sum "
     RUN lejecuta

     IF gfolio = 0 THEN
        LET lresultado = "ESTE ARCHIVO YA HA SIDO PROCESADO"
     ELSE 
        LET lresultado = "Archivo de respuesta a PROCESAR generado"
     END IF

     CALL Actualiza_etapa(6,lresultado)

  END IF

END FUNCTION

#*********************************************************************
FUNCTION Actualiza_etapa(letapa_cod,lresultado)
  DEFINE letapa_cod   DECIMAL(2,0),
         lresultado   CHAR(50),
         lcla_sel     CHAR(400),
         lhora_max    CHAR(08),
         lhora_final  CHAR(08)

  LET lcla_sel = " SELECT MAX(hora_inicial) ",
                   " FROM dis_ctrl_proceso ",
                  " WHERE folio       = ",gfolio,
                    " AND proceso_cod = 'EXC' ",
                    " AND etapa_cod   = ",letapa_cod

  PREPARE claexe3 FROM lcla_sel

  DECLARE cur_proceso3 CURSOR FOR claexe3

  OPEN cur_proceso3
    FETCH cur_proceso3 INTO lhora_max
  CLOSE cur_proceso3

  LET lhora_final   = TIME

  LET lcla_sel = " UPDATE dis_ctrl_proceso ",
                    " SET hora_final = ","'",lhora_final,"',",
                        " resultado  = ","'",lresultado,"'",
                  " WHERE folio        = ",gfolio,
                    " AND proceso_cod  = 'EXC'",
                    " AND etapa_cod    = ",letapa_cod,
                    " AND hora_inicial = ","'",lhora_max,"'"

  PREPARE claexe4 FROM lcla_sel

  EXECUTE claexe4

END FUNCTION
#*********************************************************************

FUNCTION archc_ncbzdo() 
  DEFINE l_cza       RECORD 
           fecha_creac_lote  DATE,
           consecutivo_dia   CHAR(3),
           fecha_limite_resp DATE
         END RECORD,
         l_arch      CHAR(100),
         lpermisos   CHAR(100)

  LET l_arch = g_ruta CLIPPED,"/dev_cza"

  START REPORT r_cza TO l_arch

  SELECT fecha_creac_lote, 
         consecutivo_dia, 
         fecha_limite_resp
    INTO l_cza.fecha_creac_lote,
         l_cza.consecutivo_dia,
         l_cza.fecha_limite_resp
    FROM exc_cza_exceso
   WHERE folio  = gfolio

  OUTPUT TO REPORT r_cza(l_cza.*)

  FINISH REPORT r_cza   

  LET lpermisos = "chmod 777 ",l_arch CLIPPED
  RUN lpermisos

END FUNCTION
#*********************************************************************

FUNCTION reg_02()
  DEFINE l_arch        CHAR(100),
         lmarca_entra  SMALLINT,
         limporte      DECIMAL(16,6),
         lacciones     DECIMAL(16,6),
         limp_solici   DECIMAL(20,6),
         lsubcuenta    SMALLINT,
         li            SMALLINT, 
         lpermisos     CHAR(100),
         lsiefore      SMALLINT

  LET l_arch = g_ruta CLIPPED,"/dev_det"

  START REPORT r_det TO l_arch

  DECLARE cursor_1 CURSOR FOR
  SELECT * 
    FROM exc_det_devpgo
   WHERE folio = gfolio
  ORDER BY consec_reg_lote
  FOREACH cursor_1 INTO g_det.*

    IF g_det.diag_devolucion = "01" OR g_det.diag_devolucion = "04" THEN

       ---Incrementa valor para sumario id14 layout 035609
       ---NÚMERO DE APORTACIONES ACEPTADAS A DEVOLVER
       LET gnum_apor_acep_adev = gnum_apor_acep_adev + 1 

       ---Obtiene los valores suficientes y parciales 
       IF g_det.clave_ent_orig = "001" THEN

          FOR li = 1 TO 7  

            CASE li 
              WHEN 1
                LET lsubcuenta  = 1
                LET limp_solici = g_det.monto_ret 
              WHEN 2
                LET lsubcuenta  = 1
                LET limp_solici = g_det.monto_act_ret 
              WHEN 3
                LET lsubcuenta  = 1
                LET limp_solici = g_det.imp_rnd_ret_indv 
              WHEN 4
                LET lsubcuenta  = 2
                LET limp_solici = g_det.monto_cv_pat 
              WHEN 5
                LET lsubcuenta  = 2
                LET limp_solici = g_det.monto_act_cv_pat 
              WHEN 6
                LET lsubcuenta  = 2
                LET limp_solici = g_det.imp_rnd_cv_indv_pat 
              WHEN 7
                LET lsubcuenta  = 5
                LET limp_solici = g_det.monto_cuo_soc 
            END CASE

            LET lsiefore = 0
            CALL obtiene_importe(g_det.nss, lsubcuenta,
                                 g_det.consec_reg_lote, limp_solici) 
                                 RETURNING limporte, lacciones, lsiefore 
            
            ---- Tiene que regresar 0 cuando es insuficiente
            CASE li 
              WHEN 1
                LET g_det.monto_ret           = limporte
              WHEN 2
                LET g_det.monto_act_ret       = limporte 
              WHEN 3
                LET g_det.imp_rnd_ret_indv    = limporte 
              WHEN 4
                LET g_det.monto_cv_pat        = limporte 
              WHEN 5
                LET g_det.monto_act_cv_pat    = limporte 
              WHEN 6
                LET g_det.imp_rnd_cv_indv_pat = limporte 
              WHEN 7
                LET g_det.monto_cuo_soc       = limporte 
                
                ---Incrementa valor para sumario id12 layout 035609
                ---IMPORTE TOTAL CUOTAS GUBERNAMENTALES A DEVOLVER
                LET gmonto_tot_gub = gmonto_tot_gub + limporte
            END CASE

            --- Llena tabla temporal para archivo detalle 08
            --- Cobranza de importes a validar (parciales)
            CALL llena_pre08(lsiefore, limporte)

          END FOR

          --- Llena tabla temporal para archivo detalle 08 
          --- Cobranza de importes que no se validan 
          CALL llena_pre08(lsiefore, g_det.monto_cv_tra)
          CALL llena_pre08(lsiefore, g_det.monto_act_cv_tra)
          CALL llena_pre08(lsiefore, g_det.imp_rnd_cv_indv_tra)

       END IF

       IF g_det.clave_ent_orig = '002' THEN

          LET lsubcuenta = 4

          LET limp_solici = g_det.monto_apor_pat_viv

          CALL obtiene_importe(g_det.nss, lsubcuenta, g_det.consec_reg_lote,
                               limp_solici) 
                               RETURNING limporte, lacciones, lsiefore 
   
          IF limporte > 0 THEN
             LET g_det.monto_apor_pat_viv = limporte
             LET g_det.num_viv_aport_pat  = lacciones
          END IF
            
       END IF
    ELSE
       IF g_det.diag_devolucion = "02" THEN
          ---Incrementa valor para sumario id15 layout 035609
          ---NÚMERO DE APORTACIONES RECHAZADAS
          LET gnum_apor_rechazada = gnum_apor_rechazada + 1
       END IF 
    END IF

    OUTPUT TO REPORT r_det()

    ---Incrementa valor para sumario id18 layout 035609
    ---NÚMERO TOTAL DE REGISTROS DENTRO DEL LOTE
    LET gnum_tot_reg = gnum_tot_reg + 1


  END FOREACH

  FINISH REPORT r_det   

  LET lpermisos = "chmod 777 ",l_arch CLIPPED
  RUN lpermisos

END FUNCTION

FUNCTION obtiene_importe(lnss, lsubcuenta, lconsec_reg_lote, limp_solici) 
  DEFINE lnss             CHAR(11),
         lsubcuenta       SMALLINT,
         lconsec_reg_lote INTEGER,
         limp_solici      DECIMAL(16,6),
         limporte         DECIMAL(16,6),
         lacciones        DECIMAL(16,6),
         lsiefore         SMALLINT

  LET limporte  =  0

  SELECT UNIQUE siefore, imp_dis_pesos, imp_dis_accion 
    INTO lsiefore, limporte, lacciones
    FROM safre_tmp:exc_devpgo_sdo
   WHERE folio           = gfolio
     AND nss             = lnss
     AND subcuenta       = lsubcuenta
     AND conse_lote      = lconsec_reg_lote
     AND imp_solicitado  = limp_solici 

  IF limporte IS NULL THEN
     LET limporte = 0
  END IF 
 
  IF lacciones IS NULL THEN
     LET lacciones = 0
  END IF 

  RETURN limporte, lacciones, lsiefore 

END FUNCTION

FUNCTION llena_pre08(lsiefore, limporte)
  DEFINE lsiefore  SMALLINT,
         limporte  DECIMAL(20,6)

  INSERT INTO safre_tmp:exc_dep08 VALUES(lsiefore, limporte)

END FUNCTION 

FUNCTION ctaPorCobrar08_001()
  DEFINE lreg    RECORD 
           siefore          SMALLINT,
           imp_dis_pesos    DECIMAL(20,6)
         END RECORD, 
         lfecha_recepcion     DATE,
         lhora_recepcion      CHAR(10),
         lestado              SMALLINT,
         lfecha_estado        DATE,
         lhora_estado         CHAR(10),
         lsiefore_desc        CHAR(20),
         lident_pago          CHAR(16),
         lmonto_soli_institu  DECIMAL(16,6),
         lfecha_liquidacion   DATE,
         lnum_aiv_solic       DECIMAL(20,6),
         limporte_rchz        DECIMAL(16,6),       
         limporte_pend        DECIMAL(16,6),
         lmonto_ret           DECIMAL(16,6),
         lmonto_act_ret       DECIMAL(16,6),
         limp_rnd_ret_indv    DECIMAL(16,6),
         lmonto_cv_pat        DECIMAL(16,6),
         lmonto_act_cv_pat    DECIMAL(16,6),
         limp_rnd_cv_indv_pat DECIMAL(16,6),
         lmonto_cuo_soc       DECIMAL(16,6),
         lmonto_cv_tra        DECIMAL(16,6),
         lmonto_act_cv_tra    DECIMAL(16,6),
         limp_rnd_cv_indv_tra DECIMAL(16,6)    

  LET lestado          = 3
  LET lfecha_estado    = TODAY
  LET lhora_estado     = TIME

  SELECT ident_pago, monto_soli_institu, fecha_liquidacion, 
         num_aiv_solic 
    INTO lident_pago, lmonto_soli_institu, lfecha_liquidacion,
         lnum_aiv_solic 
    FROM exc_dep_devpgo 
   WHERE folio       = gfolio
     AND ident_pago[14,15] = "71"

  IF lident_pago IS NULL OR lident_pago = '                '
     OR lident_pago = '0000000000000000' THEN
     RETURN
  END IF

  IF lmonto_soli_institu IS NULL THEN
     LET lmonto_soli_institu = 0
  END IF

  ---Incrementa valor para sumario id10 layout 035609 
  ---IMPORTE TOTAL RETIRO CESANTÍA Y VEJEZ A DEVOLVER
  LET gmonto_tot_rcv = 0                                    

  DECLARE cur_cob08 CURSOR FOR
  SELECT siefore, SUM(ROUND(importe,2))    
    FROM safre_tmp:exc_dep08              
   WHERE siefore > 0            
  GROUP BY siefore 
  ORDER BY siefore
  FOREACH cur_cob08 INTO lreg.siefore, lreg.imp_dis_pesos 

    IF lreg.imp_dis_pesos IS NULL THEN
       LET lreg.imp_dis_pesos = 0 
    END IF

    LET lsiefore_desc = NULL
	
	SELECT siech_razon_social
	INTO lsiefore_desc 
	FROM safre_ing:tc_siefore_local 
    WHERE  siesm_cod_siefore = lreg.siefore

    INSERT INTO exc_dep_devpgo
         VALUES (gfolio,
                 lestado,
                 lfecha_estado,
                 lhora_estado,
                 '08',
                 '03',
                 lident_pago,
                 lmonto_soli_institu,
                 lfecha_liquidacion,
                 lreg.imp_dis_pesos,
                 0,
                 0,
                 lnum_aiv_solic,
                 0,
                 0,
                 0,
                 0,
                 0,
                 0,
                 lsiefore_desc,
                 lreg.siefore) 

    ---Incrementa valor para sumario id10 layout 035609 
    ---IMPORTE TOTAL RETIRO CESANTÍA Y VEJEZ A DEVOLVER
    LET gmonto_tot_rcv = gmonto_tot_rcv + lreg.imp_dis_pesos  

  END FOREACH 

  LET limporte_rchz        = 0
  LET lmonto_ret           = 0 
  LET lmonto_act_ret       = 0
  LET limp_rnd_ret_indv    = 0
  LET lmonto_cv_pat        = 0
  LET lmonto_act_cv_pat    = 0
  LET limp_rnd_cv_indv_pat = 0
  LET lmonto_cuo_soc       = 0

  SELECT SUM(ROUND(monto_ret,2)),
         SUM(ROUND(monto_act_ret,2)),
         SUM(ROUND(imp_rnd_ret_indv,2)), 
         SUM(ROUND(monto_cv_pat,2)),
         SUM(ROUND(monto_act_cv_pat,2)),
         SUM(ROUND(imp_rnd_cv_indv_pat,2)),
         SUM(ROUND(monto_cuo_soc,2)), 
         SUM(ROUND(monto_cv_tra,2)), 
         SUM(ROUND(monto_act_cv_tra,2)), 
         SUM(ROUND(imp_rnd_cv_indv_tra,2)) 
    INTO lmonto_ret,
         lmonto_act_ret,
         limp_rnd_ret_indv,
         lmonto_cv_pat,
         lmonto_act_cv_pat,
         limp_rnd_cv_indv_pat,
         lmonto_cuo_soc,
         lmonto_cv_tra,
         lmonto_act_cv_tra,
         limp_rnd_cv_indv_tra
    FROM exc_det_devpgo
   WHERE folio          = gfolio
     AND clave_ent_orig = '001'
     AND diag_devolucion = '02'

  IF lmonto_ret IS NULL THEN
     LET lmonto_ret = 0
  END IF

  IF lmonto_act_ret IS NULL THEN
     LET lmonto_act_ret = 0
  END IF

  IF limp_rnd_ret_indv IS NULL THEN
     LET limp_rnd_ret_indv = 0
  END IF

  IF lmonto_cv_pat IS NULL THEN
     LET lmonto_cv_pat = 0
  END IF

  IF lmonto_act_cv_pat IS NULL THEN
     LET lmonto_act_cv_pat = 0
  END IF

  IF limp_rnd_cv_indv_pat IS NULL THEN
     LET limp_rnd_cv_indv_pat = 0
  END IF

  IF lmonto_cuo_soc IS NULL THEN
     LET lmonto_cuo_soc = 0
  END IF

  IF lmonto_cv_tra IS NULL THEN
     LET lmonto_cv_tra = 0
  END IF

  IF lmonto_act_cv_tra IS NULL THEN
     LET lmonto_act_cv_tra = 0
  END IF

  IF limp_rnd_cv_indv_tra IS NULL THEN 
     LET limp_rnd_cv_indv_tra = 0
  END IF

  LET limporte_rchz  = lmonto_ret + lmonto_act_ret + limp_rnd_ret_indv + 
                       lmonto_cv_pat + lmonto_act_cv_pat + 
                       limp_rnd_cv_indv_pat + lmonto_cuo_soc + lmonto_cv_tra +
                       lmonto_act_cv_tra + limp_rnd_cv_indv_tra

  LET limporte_pend = 0

  IF limporte_rchz > 0 THEN
     LET lhora_estado     = TIME

     INSERT INTO exc_dep_devpgo
          VALUES (gfolio,
                  lestado,
                  lfecha_estado,
                  lhora_estado,
                  '08',
                  '03',
                  lident_pago,
                  lmonto_soli_institu,
                  lfecha_liquidacion,
                  0,
                  limporte_pend,
                  limporte_rchz,
                  lnum_aiv_solic,
                  0,
                  0,
                  0,
                  0,
                  0,
                  0,
                  NULL,
                  0) 
  END IF

END FUNCTION

FUNCTION ctaPorCobrar08_002()
  DEFINE limp_dis_pesos       DECIMAL(20,6),
         lfecha_recepcion     DATE,
         lhora_recepcion      CHAR(10),
         lestado              SMALLINT,
         lfecha_estado        DATE,
         lhora_estado         CHAR(10),
         lident_pago          CHAR(16),
         lmonto_soli_institu  DECIMAL(16,6),
         lfecha_liquidacion   DATE,
         lnum_aiv_solic       DECIMAL(20,6),
         limporte_rchz        DECIMAL(20,6),       
         limporte_pend        DECIMAL(20,6),
         limp_viv_acep_adev   DECIMAL(16,6),
         limp_viv_pend        DECIMAL(16,6),
         limp_viv_rchz        DECIMAL(16,6),
         lprecio_accion       DECIMAL(22,6) 

  LET lestado          = 3
  LET lfecha_estado    = TODAY

  SELECT ident_pago, monto_soli_institu, fecha_liquidacion, 
         num_aiv_solic 
    INTO lident_pago, lmonto_soli_institu, lfecha_liquidacion,
         lnum_aiv_solic 
    FROM exc_dep_devpgo 
   WHERE folio             = gfolio
     AND ident_pago[14,15] = "73"

  IF lident_pago IS NULL OR lident_pago = '                '
     OR lident_pago = '0000000000000000' THEN
     RETURN
  END IF

  IF lmonto_soli_institu IS NULL THEN
     LET lmonto_soli_institu = 0
  END IF

  LET limp_dis_pesos = 0
  SELECT SUM(ROUND(imp_dis_pesos,2)), SUM(ROUND(imp_dis_accion,2))
    INTO limp_dis_pesos, limp_viv_acep_adev 
    FROM safre_tmp:exc_devpgo_sdo
   WHERE folio         = gfolio
     AND subcuenta     = 4
     AND imp_dis_pesos > 0
     AND diagnostico  IN (1,4)

  IF limp_dis_pesos IS NULL THEN
     LET limp_dis_pesos = 0
  END IF

  IF limp_viv_acep_adev IS NULL THEN
     LET limp_viv_acep_adev = 0
  END IF

  LET limporte_rchz = 0
  SELECT SUM(ROUND(monto_apor_pat_viv,2))
    INTO limporte_rchz
    FROM exc_det_devpgo
   WHERE folio          = gfolio
     AND clave_ent_orig = '002'
     AND diag_devolucion = '02'

  IF limporte_rchz IS NULL THEN
     LET limporte_rchz = 0
  END IF

  LET limporte_pend = 0
  SELECT SUM(ROUND(monto_apor_pat_viv,2))
    INTO limporte_pend
    FROM exc_det_devpgo
   WHERE folio          = gfolio
     AND clave_ent_orig = '002'
     AND diag_devolucion = '03'

  IF limporte_pend IS NULL THEN
     LET limporte_pend = 0
  END IF
  
  LET limp_viv_rchz = 0
  SELECT SUM(ROUND(num_viv_aport_pat,2))
    INTO limp_viv_rchz 
    FROM exc_det_devpgo
   WHERE folio          = gfolio
     AND clave_ent_orig = '002'
     AND diag_devolucion = '02'

  IF limp_viv_rchz IS NULL THEN
     LET limp_viv_rchz = 0
  END IF 

  LET limp_viv_pend = 0
  SELECT SUM(ROUND(num_viv_aport_pat,2))
    INTO limp_viv_pend
    FROM exc_det_devpgo
   WHERE folio          = gfolio
     AND clave_ent_orig = '002'
     AND diag_devolucion = '03'

  IF limp_viv_pend IS NULL THEN
     LET limp_viv_pend = 0
  END IF
  
  ---Sumario id11 layout 035609
  ---IMPORTE TOTAL APORTACIÓN PATRONAL VIVIENDA A DEVOLVER
  LET gmonto_tot_pat_viv  = 0
  LET gmonto_tot_pat_viv = limp_dis_pesos

  ---Sumario id19 layout 035609
  ---NÚMERO DE APLICACIONES DE INTERESES DE VIVIENDA  
  ---POR APORTACIÓN PATRONAL DE VIVIENDA A DEVOLVER
  LET gnum_tot_par_viv    = 0
  LET gnum_tot_par_viv = limp_viv_acep_adev

  LET lhora_estado     = TIME

  INSERT INTO exc_dep_devpgo
       VALUES (gfolio,
               lestado,
               lfecha_estado,
               lhora_estado,
               '08',
               '03',
               lident_pago,
               lmonto_soli_institu,
               lfecha_liquidacion,
               0,
               0,
               0,
               lnum_aiv_solic,
               limp_viv_acep_adev,        #Acciones
               limp_viv_pend,
               limp_viv_rchz,
               limp_dis_pesos,            #Pesos
               limporte_pend,
               limporte_rchz,
               NULL,
               0) 
END FUNCTION

FUNCTION archc_dep()
  DEFINE l_arch        CHAR(100),
         lpermisos     CHAR(100)

  LET l_arch = g_ruta CLIPPED,"/dev_dep"

  START REPORT r_dep TO l_arch

  DECLARE cur_arch08  CURSOR FOR
  SELECT ident_pago,
         monto_soli_institu,
         fecha_liquidacion,
         imp_acep_rcv_adev,
         imp_pend_rcv,
         imp_rchz_rcv,
         num_aiv_solic,
         num_aiv_acep,
         num_aiv_pend,
         num_aiv_rchz,
         imp_viv_acep_adev,
         imp_viv_pend,
         imp_viv_rchz,
         siefore_desc,
         codigo_siefore 
    FROM exc_dep_devpgo 
   WHERE folio  = gfolio
     AND estado = 3
  ORDER BY ident_pago, codigo_siefore
  FOREACH cur_arch08 INTO g_dep.ident_pago,
                          g_dep.monto_soli_institu,
                          g_dep.fecha_liquidacion,
                          g_dep.imp_acep_rcv_adev,
                          g_dep.imp_pend_rcv,
                          g_dep.imp_rchz_rcv,
                          g_dep.num_aiv_solic,
                          g_dep.num_aiv_acep,
                          g_dep.num_aiv_pend,
                          g_dep.num_aiv_rchz,
                          g_dep.imp_viv_acep_adev,
                          g_dep.imp_viv_pend,
                          g_dep.imp_viv_rchz,
                          g_dep.siefore_desc,
                          g_dep.codigo_siefore 

        OUTPUT TO REPORT r_dep()            

    ---Incrementa valor para sumario id17 layout 035609
    ---NÚMERO DE REGISTROS CUENTAS POR PAGAR
      LET gnum_reg_pagar = gnum_reg_pagar + 1   
	  

    ---Incrementa valor para sumario id18 layout 035609
    ---NÚMERO TOTAL DE REGISTROS DENTRO DEL LOTE
      LET gnum_tot_reg = gnum_tot_reg + 1   


  END FOREACH

  FINISH REPORT r_dep   

  LET lpermisos = "chmod 777 ",l_arch CLIPPED
  RUN lpermisos

END FUNCTION

FUNCTION archc_sum()
  DEFINE l_arch        CHAR(100),
         lpermisos     CHAR(100)

  LET l_arch = g_ruta CLIPPED,"/dev_sum"

  START REPORT r_sum TO l_arch

  ----Se obtienen datos fijos para archivo de sumario
  SELECT fecha_creac_lote,
         consecutivo_dia,
         num_reg_aport_lote
    INTO g_sum.fecha_creac_lote,
         g_sum.consecutivo_dia,
         g_sum.num_reg_aport_lote
    FROM exc_sum_devpgo
   WHERE folio = gfolio

       
  OUTPUT TO REPORT r_sum()

  FINISH REPORT r_sum   
  LET lpermisos = "chmod 777 ",l_arch CLIPPED
  RUN lpermisos

END FUNCTION

FUNCTION cif_con()
  DEFINE l_arch        CHAR(100),
         lpermisos     CHAR(100),
         lrg_cif   RECORD 
           siefore     SMALLINT,
           subcuenta   SMALLINT,
           acciones    DECIMAL(20,6),
           pesos       DECIMAL(20,2),
           tip_mov     SMALLINT
         END RECORD,
         lsiefore_ant  SMALLINT,
         lsemafo_sie   SMALLINT,
         lejecuta      CHAR(500)

  LET l_arch  = NULL
  LET l_arch  = g_ruta CLIPPED,"/excb3_cc_cza.txt"
  START REPORT r_cif_cza TO l_arch
    OUTPUT TO REPORT r_cif_cza()       --- Los precios se obtien  de EXCB136
  FINISH REPORT r_cif_cza

  LET lsiefore_ant = NULL
  LET lsemafo_sie  = 0
  LET gtotsieacep  = 0
  LET l_arch       = NULL
  LET l_arch       = g_ruta CLIPPED,"/excb3_cc_det.txt"

  START REPORT r_cif_det TO l_arch

  DECLARE cur_cif CURSOR FOR
  SELECT siefore, subcuenta, SUM(ROUND(imp_dis_accion,6)),
         SUM(ROUND(imp_dis_pesos,2)), tipo_movimiento
    FROM safre_tmp:exc_devpgo_sdo
   WHERE folio         = gfolio
     AND diagnostico  IN (1,4)
     AND imp_dis_pesos > 0
  GROUP BY siefore, subcuenta, tipo_movimiento 
  ORDER BY siefore, subcuenta, tipo_movimiento
  FOREACH cur_cif INTO lrg_cif.siefore, lrg_cif.subcuenta,
                       lrg_cif.acciones, lrg_cif.pesos,
                       lrg_cif.tip_mov

    IF lsiefore_ant IS NULL THEN
       LET lsemafo_sie  = 1
    ELSE
       IF lsiefore_ant <> lrg_cif.siefore THEN
          LET lsemafo_sie = 1
       END IF
    END IF

    IF lsemafo_sie = 1 THEN

       SELECT COUNT(UNIQUE nss) INTO gtotsieacep
         FROM safre_tmp:exc_devpgo_sdo
        WHERE folio         = gfolio
          AND siefore       = lrg_cif.siefore
          AND diagnostico  IN (1,4)
          AND imp_dis_pesos > 0

    END IF

    OUTPUT TO REPORT r_cif_det(lrg_cif.*)

    LET lsemafo_sie  = 0
    LET lsiefore_ant = lrg_cif.siefore
    LET gtotsieacep  = 0

  END FOREACH

  FINISH REPORT r_cif_det

  LET lejecuta = NULL
  LET lejecuta = " cat ",g_ruta CLIPPED,"/excb3_cc_cza.txt ",
                         g_ruta CLIPPED,"/excb3_cc_det.txt > ",
                         g_ruta CLIPPED,"/excb003_cc.txt"
  RUN lejecuta

  LET l_arch  = NULL
  LET l_arch  = g_ruta CLIPPED,"/excb003_cc.txt"

  LET lpermisos = "chmod 777 ",l_arch CLIPPED
  RUN lpermisos

END FUNCTION

FUNCTION  envia_mail()
  DEFINE lcadena_mail CHAR(550),
         lejecuta     CHAR(250),
         l_arch       CHAR(100)

  LET l_arch  = NULL
  LET l_arch  = "excb003_cc"

  LET lejecuta = "sh /safre/est/shells/env_mail_gral.sh ",
                 "Informe/archivo/respuesta/dev/pago ",
                 l_arch CLIPPED," ","txt"," ",
                 g_ruta CLIPPED," ",
                 programa CLIPPED
                   
  RUN lejecuta

END FUNCTION

REPORT r_cza(rcza)
  DEFINE rcza       RECORD
           fecha_creac_lote  DATE,
           consecutivo_dia   CHAR(3),
           fecha_limite_resp DATE
         END RECORD 

  OUTPUT
    PAGE     LENGTH 1
    LEFT     MARGIN 0
    RIGHT    MARGIN 0
    TOP      MARGIN 0
    BOTTOM   MARGIN 0

  FORMAT

    ON EVERY ROW
      PRINT COLUMN 001, "01",
            COLUMN 003, "03",
            COLUMN 005, "56",
            COLUMN 007, gtipo_ent_origen,
            COLUMN 009, g_tabafore.codigo_afore USING "&&&",
            COLUMN 012, "03",
            COLUMN 014, "001",
            COLUMN 017, rcza.fecha_creac_lote USING "YYYYMMDD",
            COLUMN 025, rcza.consecutivo_dia,
            COLUMN 028, rcza.fecha_limite_resp USING "YYYYMMDD",
            COLUMN 036, 265 SPACES
END REPORT

REPORT r_det()
  DEFINE rmonto_ret            DECIMAL(16),
         rmonto_cv_pat         DECIMAL(16),
         rmonto_cv_tra         DECIMAL(16),
         rmonto_cuo_soc        DECIMAL(16),
         rmonto_act_ret        DECIMAL(16),
         rmonto_act_cv_pat     DECIMAL(16),
         rmonto_act_cv_tra     DECIMAL(16),
         rmonto_apor_pat_viv   DECIMAL(16),
         rnum_viv_aport_pat    DECIMAL(20),
         rimp_rnd_ret_indv     DECIMAL(16),
         rimp_rnd_cv_indv_pat  DECIMAL(16),
         rimp_rnd_cv_indv_tra  DECIMAL(16),
         rnum_viv_aport_pat_d2 DECIMAL(20,2),
         rnum_viv_aport_pat_ch CHAR(15)
          
  OUTPUT
    PAGE     LENGTH 1
    LEFT     MARGIN 0
    RIGHT    MARGIN 0
    TOP      MARGIN 0
    BOTTOM   MARGIN 0

  FORMAT

    ON EVERY ROW
      LET rmonto_ret            = g_det.monto_ret           * 100
      LET rmonto_cv_pat         = g_det.monto_cv_pat        * 100
      LET rmonto_cv_tra         = g_det.monto_cv_tra        * 100
      LET rmonto_cuo_soc        = g_det.monto_cuo_soc       * 100
      LET rmonto_act_ret        = g_det.monto_act_ret       * 100
      LET rmonto_act_cv_pat     = g_det.monto_act_cv_pat    * 100
      LET rmonto_act_cv_tra     = g_det.monto_act_cv_tra    * 100
      LET rmonto_apor_pat_viv   = g_det.monto_apor_pat_viv  * 100

      LET rnum_viv_aport_pat_d2 = g_det.num_viv_aport_pat 
      LET rnum_viv_aport_pat    = rnum_viv_aport_pat_d2     * 100
      LET rnum_viv_aport_pat_ch = rnum_viv_aport_pat USING "&&&&&&&&&&&","0000"
      LET rimp_rnd_ret_indv     = g_det.imp_rnd_ret_indv    * 100
      LET rimp_rnd_cv_indv_pat  = g_det.imp_rnd_cv_indv_pat * 100
      LET rimp_rnd_cv_indv_tra  = g_det.imp_rnd_cv_indv_tra * 100

      PRINT COLUMN 001, g_det.tipo_registro,
            COLUMN 002, g_det.ident_servicio,
            COLUMN 005, g_det.consec_reg_lote     USING "&&&&&&&&",
            COLUMN 013, g_det.nss,
            COLUMN 024, g_det.clave_ent_orig,
            COLUMN 027, g_det.rfc,
            COLUMN 040, g_det.curp,
            COLUMN 058, g_det.nom_trabajador,
            COLUMN 108, g_det.periodo_pago,
            COLUMN 114, g_det.fecha_pago          USING "YYYYMMDD",
            COLUMN 122, g_det.fecha_valor_rcv     USING "YYYYMMDD",
            COLUMN 130, g_det.fecha_valor_viv     USING "YYYYMMDD",
            COLUMN 138, g_det.folio_pago_sua,
            COLUMN 144, g_det.clave_ent_recep,
            COLUMN 147, g_det.reg_patronal_imss,
            COLUMN 158, rmonto_ret                USING "&&&&&&&&&",
            COLUMN 167, rmonto_cv_pat             USING "&&&&&&&&&",
            COLUMN 176, rmonto_cv_tra             USING "&&&&&&&&&", 
            COLUMN 185, rmonto_cuo_soc            USING "&&&&&&&&&",
            COLUMN 194, rmonto_act_ret            USING "&&&&&&&&&",
            COLUMN 203, rmonto_act_cv_pat         USING "&&&&&&&&&",
            COLUMN 212, rmonto_act_cv_tra         USING "&&&&&&&&&",
            COLUMN 221, rmonto_apor_pat_viv       USING "&&&&&&&&&",
            COLUMN 230, g_det.dias_cotz_bimestre  USING "&&",
            COLUMN 232, rnum_viv_aport_pat_ch,
            COLUMN 247, rimp_rnd_ret_indv         USING "&&&&&&&&&",
            COLUMN 256, rimp_rnd_cv_indv_pat      USING "&&&&&&&&&", 
            COLUMN 265, rimp_rnd_cv_indv_tra      USING "&&&&&&&&&",
            COLUMN 274, g_det.fec_origen_solic    USING "YYYYMMDD",
            COLUMN 282, g_det.diag_devolucion,
            COLUMN 284, g_det.motivo_devolucion   USING "&&&",
            COLUMN 287, 14 SPACES                   #13 SPACES
      
END REPORT

REPORT r_dep()
  DEFINE rmonto_soli_institu  DECIMAL(16),
         rimp_acep_rcv_adev   DECIMAL(16),
         rimp_pend_rcv        DECIMAL(16),
         rimp_rchz_rcv        DECIMAL(16),
         rnum_aiv_solic       DECIMAL(20),
         rnum_aiv_acep        DECIMAL(20),
         rnum_aiv_pend        DECIMAL(20),
         rnum_aiv_rchz        DECIMAL(20),
         rimp_viv_acep_adev   DECIMAL(16),
         rimp_viv_pend        DECIMAL(16),
         rimp_viv_rchz        DECIMAL(16),
         rnum_aiv_acep_d2     DECIMAL(20,2),
         rnum_aiv_pend_d2     DECIMAL(20,2),
         rnum_aiv_rchz_d2     DECIMAL(20,2),
         rnum_aiv_acep_ch     CHAR(18),
         rnum_aiv_pend_ch     CHAR(18),
         rnum_aiv_rchz_ch     CHAR(18) 
  OUTPUT
    PAGE     LENGTH 1
    LEFT     MARGIN 0
    RIGHT    MARGIN 0
    TOP      MARGIN 0
    BOTTOM   MARGIN 0

  FORMAT

    ON EVERY ROW
      LET rmonto_soli_institu = g_dep.monto_soli_institu * 100
      LET rimp_acep_rcv_adev  = g_dep.imp_acep_rcv_adev  * 100
      LET rimp_pend_rcv       = g_dep.imp_pend_rcv       * 100
      LET rimp_rchz_rcv       = g_dep.imp_rchz_rcv       * 100
      LET rnum_aiv_solic      = g_dep.num_aiv_solic      * 1000000


      LET rnum_aiv_acep_d2    = g_dep.num_aiv_acep
      LET rnum_aiv_acep       = rnum_aiv_acep_d2  * 100
      LET rnum_aiv_acep_ch    = rnum_aiv_acep USING "&&&&&&&&&&&&&&","0000" 

      LET rnum_aiv_pend_d2    = g_dep.num_aiv_pend 
      LET rnum_aiv_pend       = rnum_aiv_pend_d2  * 100
      LET rnum_aiv_pend_ch    = rnum_aiv_pend USING "&&&&&&&&&&&&&&","0000"

      LET rnum_aiv_rchz_d2    = g_dep.num_aiv_rchz 
      LET rnum_aiv_rchz       = rnum_aiv_rchz_d2  * 100
      LET rnum_aiv_rchz_ch    = rnum_aiv_rchz USING "&&&&&&&&&&&&&&","0000"


      LET rimp_viv_acep_adev  = g_dep.imp_viv_acep_adev  * 100
      LET rimp_viv_pend       = g_dep.imp_viv_pend       * 100
      LET rimp_viv_rchz       = g_dep.imp_viv_rchz       * 100

      PRINT COLUMN 001, "08",
            COLUMN 003, "03",
            COLUMN 005, g_dep.ident_pago,
            COLUMN 021, rmonto_soli_institu     USING "&&&&&&&&&&&&&&&", 
            COLUMN 036, g_dep.fecha_liquidacion USING "YYYYMMDD",
            COLUMN 044, rimp_acep_rcv_adev      USING "&&&&&&&&&&&&&&&", 
            COLUMN 059, rimp_pend_rcv           USING "&&&&&&&&&&&&&&&",
            COLUMN 074, rimp_rchz_rcv           USING "&&&&&&&&&&&&&&&",
            COLUMN 089, rnum_aiv_solic          USING "&&&&&&&&&&&&&&&&&&",

            COLUMN 107, rnum_aiv_acep_ch        USING "&&&&&&&&&&&&&&&&&&",
            COLUMN 125, rnum_aiv_pend_ch        USING "&&&&&&&&&&&&&&&&&&",
            COLUMN 143, rnum_aiv_rchz_ch        USING "&&&&&&&&&&&&&&&&&&", 

            COLUMN 161, rimp_viv_acep_adev      USING "&&&&&&&&&&&&&&&",
            COLUMN 176, rimp_viv_pend           USING "&&&&&&&&&&&&&&&",  
            COLUMN 191, rimp_viv_rchz           USING "&&&&&&&&&&&&&&&", 
            COLUMN 206, g_dep.siefore_desc,
            COLUMN 214, g_dep.codigo_siefore    USING "&&&",
            COLUMN 217, 84 SPACES            #83 SPACES
END REPORT


REPORT r_sum()
  DEFINE rmonto_tot_rcv      DECIMAL(16),
         rmonto_tot_pat_viv  DECIMAL(16),
         rmonto_tot_gub      DECIMAL(16),
         rnum_tot_par_viv    DECIMAL(20)
     
  OUTPUT
    PAGE     LENGTH 1
    LEFT     MARGIN 0
    RIGHT    MARGIN 0
    TOP      MARGIN 0
    BOTTOM   MARGIN 0

  FORMAT

    ON EVERY ROW

      IF gmonto_tot_rcv IS NULL THEN
         LET gmonto_tot_rcv = 0
      END IF

      IF gmonto_tot_pat_viv IS NULL THEN
         LET gmonto_tot_pat_viv = 0
      END IF

      IF gmonto_tot_gub IS NULL THEN
         LET gmonto_tot_gub = 0
      END IF

      IF gnum_tot_par_viv IS NULL THEN
         LET gnum_tot_par_viv = 0
      END IF

      LET rmonto_tot_rcv      = gmonto_tot_rcv     * 100 
      LET rmonto_tot_pat_viv  = gmonto_tot_pat_viv * 100
      LET rmonto_tot_gub      = gmonto_tot_gub     * 100
      LET rnum_tot_par_viv    = gnum_tot_par_viv   * 1000000 

      PRINT COLUMN 001, "09",
            COLUMN 003, "03",
            COLUMN 005, "56",
            COLUMN 007, gtipo_ent_origen,
            COLUMN 009, g_tabafore.codigo_afore USING "&&&",
            COLUMN 012, "03",
            COLUMN 014, "001",
            COLUMN 017, g_sum.fecha_creac_lote USING "YYYYMMDD",
            COLUMN 025, g_sum.consecutivo_dia  USING "&&&",
            COLUMN 028, rmonto_tot_rcv         USING "&&&&&&&&&&&&&&&",
            COLUMN 043, rmonto_tot_pat_viv     USING "&&&&&&&&&&&&&&&",
            COLUMN 058, rmonto_tot_gub         USING "&&&&&&&&&&&&&&&",
            COLUMN 073, g_sum.num_reg_aport_lote USING "&&&&&&&&",
            COLUMN 081, gnum_apor_acep_adev    USING "&&&&&&",
            COLUMN 087, gnum_apor_rechazada    USING "&&&&&&",
            COLUMN 093, gnum_apor_pendiente    USING "&&&&&&",
			--COLUMN 099, gnum_reg_pagar         USING "&&&&&&",
			COLUMN 099, regpagar, 
	        COLUMN 105, gnum_tot_reg           USING "&&&&&&",
            COLUMN 111, rnum_tot_par_viv       USING "&&&&&&&&&&&&&&&&&&&", 
            COLUMN 130, 171 SPACES                       # 170 SPACES

END REPORT
           
REPORT r_cif_cza()
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
        IF ri = 1 THEN
           PRINT COLUMN  1,  'EXCB103',
                 COLUMN  12, 'SURA AFORE',
                 COLUMN  50, TODAY  USING "DD/MM/YYYY",
                 COLUMN  65, 'PAGINA',
                 COLUMN  72, PAGENO USING "#####"
           PRINT COLUMN  05, "REPORTE DE CIFRAS CONTROL GENERACION DE ARCHIVO ",
                             "DE RESPUESTA: "
           PRINT COLUMN  25, gtitulo_reporte CLIPPED, "  FOLIO  : ",
                             gfolio USING "#########" 
        END IF
      
        IF garr_prec[ri].siefore <> 0 THEN
           PRINT COLUMN 025, "Precio S",
                             garr_prec[ri].siefore USING "##&","  ",
                             garr_prec[ri].precio  USING "#&.######"
        END IF
      END FOR

END REPORT

REPORT r_cif_det(rcif)
  DEFINE rcif   RECORD 
           siefore    SMALLINT,
           subcuenta  SMALLINT,
           acciones   DECIMAL(20,6),
           pesos      DECIMAL(16,2),
           tip_mov    SMALLINT 
         END RECORD

  OUTPUT

    PAGE   LENGTH  90
    LEFT   MARGIN   0
    RIGHT  MARGIN 160
    TOP    MARGIN   0
    BOTTOM MARGIN   0

  FORMAT
    PAGE HEADER
      PRINT COLUMN 001, "SIEFORE",
            COLUMN 009, "SUBCTA",
            COLUMN 016, "T.MOVTO",
            COLUMN 024, "TOT_NSS",
            COLUMN 033, "   TITULOS   ",
            COLUMN 053, "    PESOS    "
      PRINT
    ON EVERY  ROW
      PRINT COLUMN 001, rcif.siefore   USING "###&",
            COLUMN 011, rcif.subcuenta USING "#&",
            COLUMN 018, rcif.tip_mov   USING "###",
            COLUMN 024, gtotsieacep    USING "###,###",
            COLUMN 025, rcif.acciones  USING "###,###,##&.&&&&&&",
            COLUMN 050, rcif.pesos     USING "$$$,$$$,$$&.&&"

END REPORT

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
         LET vin_priv_ini = 3734                 ----EXCB103
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
