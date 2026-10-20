#*****************************************************************************#
#Propietario    => SURA                                                       #
#Programa       => EXCB136                                                    #
#  Febrero 2011 => FUNCION DIAGNOSTICO DEVOLUCION DE PAGOS EN EXCESO PARA     #
#                  CARGA, RESPUESTA Y LIQUIDACION.  RQ19435_PJF               #
#*****************************************************************************#
# Diciembre 2014 => Cambiar diagnostico PENDIENTE por Rechazos, omitir siefore#
#                   5 notificar en detalle 08 del archivo de envio solo cuando#
#                   existan rechazos. RQ21718_PJF                             #
###############################################################################
# Diciembre 2015 => Integrar funcion fn_precio_dia y validar siefore por      #
#                   catalogo tc_siefore_local. RQ25372_PJF                    #
###############################################################################
# Junio 2019    => REQ 43365 TDF                                              # 
###############################################################################
# Junio 2020     => Obtener precio vivienda de tc_exc_precio_viv RQ49796_JIF  #
###############################################################################
DATABASE safre_af
GLOBALS
  DEFINE gtot_arr_prec     SMALLINT,
         garr_prec    ARRAY[600] OF RECORD
           siefore         SMALLINT,
           razon_social    CHAR(50),
           precio          DECIMAL(19,6)
         END RECORD 
END GLOBALS

FUNCTION validacion(lfolio)
  DEFINE lfolio                INTEGER,
         lreg        RECORD
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
         lmarca_entra          SMALLINT,  
         lcodigo_rechazo       SMALLINT,
         ldiagnostico          SMALLINT,
         lexiste               SMALLINT,
         li                    SMALLINT,
         lsubcuenta            SMALLINT,
         lsiefore              SMALLINT,
         lconse_reg            SMALLINT 

  CALL limpia_exc_devpgo_sdo(lfolio) #Limpia la tabla safre_tmp:exc_devpgo_sdo
  CALL ObtenerPrecios()              #Obtiene los precios del dia 

  DECLARE cursor_excdev CURSOR FOR
  SELECT nss, clave_ent_orig, consec_reg_lote, folio_pago_sua,  
         periodo_pago,
         monto_ret,                
         monto_act_ret,            
         imp_rnd_ret_indv,         
         monto_cv_pat,             
         monto_act_cv_pat,         
         imp_rnd_cv_indv_pat,      
         monto_cuo_soc,            
         monto_apor_pat_viv,       
         num_viv_aport_pat         
    FROM exc_det_devpgo
   WHERE folio = lfolio
  FOREACH cursor_excdev INTO lreg.nss, lreg.clave_ent_orig,
                             lreg.consec_reg_lote, lreg.folio_pago_sua,
                             lreg.periodo_pago,
                             lreg.monto_ret,
                             lreg.monto_act_ret,
                             lreg.imp_rnd_ret_indv,
                             lreg.monto_cv_pat,
                             lreg.monto_act_cv_pat,
                             lreg.imp_rnd_cv_indv_pat,
                             lreg.monto_cuo_soc,
                             lreg.monto_apor_pat_viv,
                             lreg.num_viv_aport_pat 

    CASE lreg.clave_ent_orig
      WHEN '001' 
        LET lmarca_entra = 540
      WHEN '002' 
        LET lmarca_entra = 542
    END CASE 

    LET lexiste = 0
    SELECT COUNT(*) 
      INTO lexiste 
      FROM afi_mae_afiliado
     WHERE n_seguro = lreg.nss

    IF lexiste IS NULL THEN
       LET lexiste = 0
    END IF

    IF lexiste = 0 THEN
       LET ldiagnostico = 2
       LET lcodigo_rechazo = 588

       CALL actualiza_reg(lfolio,lreg.nss,lreg.consec_reg_lote,
                          ldiagnostico,lcodigo_rechazo,
                          lmarca_entra)
    ELSE
       -- Valida convivencia de marcas 

       CALL convivencia(lreg.nss,lmarca_entra) RETURNING lcodigo_rechazo

       IF lcodigo_rechazo <> 0 THEN

          LET ldiagnostico    = 2       
          LET lcodigo_rechazo = 382    

          CALL actualiza_reg(lfolio,lreg.nss,lreg.consec_reg_lote,
                             ldiagnostico,lcodigo_rechazo,
                             lmarca_entra)  

       ELSE   

          --- Ingresa saldo por subcuenta y nss en tabla tmp para(001 IMSS)
          IF lreg.clave_ent_orig  = '001' THEN
             FOR li = 1 TO 3

               IF li = 3 THEN 
                  LET lsubcuenta = 5
               ELSE
                  LET lsubcuenta = li
               END IF

               SELECT codigo_siefore INTO lsiefore
                 FROM cta_regimen
                WHERE nss       = lreg.nss
                  AND subcuenta = lsubcuenta 

               LET lconse_reg = 0
               CALL ingresa_sdo_tab_tmp(lfolio,lreg.nss,lsubcuenta,lsiefore)
                                        RETURNING lconse_reg
               
               CASE lsubcuenta 
                 WHEN 1
                   CALL diag_por_movimiento(lfolio, lreg.nss, 
                                            lreg.consec_reg_lote,
                                            lsiefore,
                                            lsubcuenta,
                                            lconse_reg,
                                            lreg.monto_ret,
                                            lreg.monto_act_ret,
                                            lreg.imp_rnd_ret_indv,
                                            lreg.periodo_pago)
                 WHEN 2
                   CALL diag_por_movimiento(lfolio, lreg.nss,
                                            lreg.consec_reg_lote,
                                            lsiefore,
                                            lsubcuenta,
                                            lconse_reg,
                                            lreg.monto_cv_pat,
                                            lreg.monto_act_cv_pat,
                                            lreg.imp_rnd_cv_indv_pat,
                                            lreg.periodo_pago)
                 WHEN 5
                   CALL diag_por_movimiento(lfolio, lreg.nss,
                                            lreg.consec_reg_lote,
                                            lsiefore,
                                            lsubcuenta,
                                            lconse_reg,
                                            lreg.monto_cuo_soc,
                                            lreg.monto_cuo_soc,
                                            lreg.monto_cuo_soc,
                                            lreg.periodo_pago)
               END CASE

             END FOR
          END IF

          --- Ingresa saldo por subcuenta y nss en tabla_tmp para(002 INFONAVIT)

          IF lreg.clave_ent_orig  = '002' THEN

             LET lsubcuenta = 4  
             LET lsiefore   = 11
             LET lconse_reg = 0
             
             CALL ingresa_sdo_tab_tmp(lfolio, lreg.nss, lsubcuenta, lsiefore) 
                                      RETURNING lconse_reg 

             CALL diag_por_movimiento(lfolio, lreg.nss,
                                      lreg.consec_reg_lote,
                                      lsiefore,
                                      lsubcuenta,
                                      lconse_reg,
                                      lreg.monto_apor_pat_viv,
                                      lreg.num_viv_aport_pat,
                                      lreg.num_viv_aport_pat,
                                      lreg.periodo_pago)
          END IF 

          ---- Actualiza el diagnostico despues de evaluar todas las subcuentas

          CALL obtiene_diagnostico_final(lfolio,lreg.nss,lreg.consec_reg_lote)
                                        RETURNING ldiagnostico

          IF ldiagnostico = 2 THEN
             LET lcodigo_rechazo = 382
             CALL actualiza_reg(lfolio,lreg.nss,lreg.consec_reg_lote,
                                ldiagnostico,lcodigo_rechazo,
                                lmarca_entra) 
          ELSE
             CALL marca_sufi_parci(lfolio,lreg.nss,lmarca_entra,ldiagnostico,
                                   lreg.consec_reg_lote,lreg.clave_ent_orig)
          END IF

       END IF
    END IF
  END FOREACH

  DISPLAY "VALIDACION Y PROVISION TERMINADA,ETAPA 4"

END FUNCTION     #validacion()

FUNCTION ObtenerPrecios()
  DEFINE lqry_precio  CHAR(100),
         lgrupo       SMALLINT,
         lfec_precio  DATE

  LET lfec_precio   = TODAY
  LET gtot_arr_prec = 1
  LET lqry_precio   = NULL
  LET lqry_precio   = "EXECUTE FUNCTION fn_precio_dia (?,?)"

  FOR lgrupo = 1 TO 3

    IF lgrupo = 2 THEN
       CONTINUE FOR
    END IF

    PREPARE eje_fn_prec FROM lqry_precio
    DECLARE cur_prec CURSOR FOR eje_fn_prec
    FOREACH cur_prec USING lgrupo, lfec_precio
                      INTO garr_prec[gtot_arr_prec].siefore,
                           garr_prec[gtot_arr_prec].razon_social,
                           garr_prec[gtot_arr_prec].precio

      IF garr_prec[gtot_arr_prec].siefore = 11 THEN        #RQ49796_JIF
          SELECT NVL(excde_precio_dia,0) INTO garr_prec[gtot_arr_prec].precio
            FROM safre_ing:tc_exc_precio_viv
           WHERE excsm_cod_siefore = garr_prec[gtot_arr_prec].siefore
             AND excdt_fvaluacion  = lfec_precio
      END IF                                               #RQ49796_JIF      

      LET gtot_arr_prec = gtot_arr_prec + 1

    END FOREACH

  END FOR

  LET gtot_arr_prec = gtot_arr_prec - 1

END FUNCTION

FUNCTION limpia_exc_devpgo_sdo(lfolio) 
  DEFINE lfolio INTEGER

  #Limpia tabla ya que se diagnostica en carga, respuesta y liquidacion

  DELETE FROM safre_tmp:exc_devpgo_sdo WHERE folio = lfolio

END FUNCTION

FUNCTION ingresa_sdo_tab_tmp(lfolio,lnss,lsubcuenta,lsiefore)
  DEFINE lfolio           INTEGER,
         lnss             CHAR(11),
         lsubcuenta       SMALLINT,
         lsiefore         SMALLINT,
         lgrupo           SMALLINT,
         lsubcta_func     SMALLINT,
         lsie_func        SMALLINT,
         lmonto_acci      DECIMAL(16,6),
         lmonto_pesos     DECIMAL(16,6),
         lconse_reg       SMALLINT,
         ldiagnostico     SMALLINT,
         lconsec_reg_lote INTEGER,
         ltipo_movimiento SMALLINT,
         lmonto_solici    DECIMAL(16,6),
         limp_disponible  DECIMAL(16,6),
         lid_aportante    CHAR(11),
         leje_sdo_sie     CHAR(250),
         lhoy             DATE           

  LET lconse_reg = 0
  LET lgrupo     = 0
  LET lhoy       = TODAY
   
  SELECT MAX(conse_reg) INTO lconse_reg
    FROM safre_tmp:exc_devpgo_sdo
   WHERE folio       = lfolio
     AND nss         = lnss
     AND subcuenta   = lsubcuenta

  IF lconse_reg IS NULL THEN
     LET lconse_reg = 0
  END IF 
 
  IF lconse_reg = 0 THEN
  
     --- Obtiene saldos 
   
     LET leje_sdo_sie = " EXECUTE PROCEDURE fn_saldo_dia_sie (?,?,?,?,?) "
     PREPARE llama_sdo_sie FROM leje_sdo_sie
     DECLARE cur_sdosie CURSOR FOR llama_sdo_sie 
     OPEN cur_sdosie USING lnss,                 #Numero de seguro social 
                           lsubcuenta,           #Subcuenta
                           lsiefore,             #Siefore
                           lgrupo,               #Grupo
                           lhoy                  #Fecha valuacion 
     FETCH cur_sdosie INTO lsubcta_func,
                           lsie_func,
                           lmonto_acci,
                           lmonto_pesos
     CLOSE cur_sdosie

     IF lmonto_acci IS NULL THEN
        LET lmonto_acci  = 0
     END IF 
            
     IF lmonto_pesos IS NULL THEN
        LET lmonto_pesos = 0
     END IF 

     IF lsubcuenta = 4 THEN
        LET lmonto_pesos = lmonto_acci  
     END IF
            
     --- Determina diagnostico 

     LET ldiagnostico  = 0
    
     --- Se inicializan datos por tratarse del primer registro
     LET lconsec_reg_lote = 0
     LET lconse_reg       = 1
     LET ltipo_movimiento = 0
     LET lmonto_solici    = 0
     LET limp_disponible  = 0
     LET lid_aportante    = "SALDO_SBCTA"

  
     ---- Inserta primer registro de nss en exc_devpgo_sdo
     CALL insert_exc_devpgo_sdo(lfolio,lnss,lconsec_reg_lote,lconse_reg,
                            ltipo_movimiento,lsiefore,
                            lsubcuenta,lmonto_solici,limp_disponible,
                            lmonto_pesos,lid_aportante,ldiagnostico,
                            lmonto_acci)
  END IF

  RETURN lconse_reg

END FUNCTION

FUNCTION diag_por_movimiento(lfolio,lnss,lconsec_reg_lote,lsiefore,
                             lsubcuenta,lconse_reg,lmonto_soli_1,
                             lmonto_soli_2,lmonto_soli_3,lperiodo_pago)
  DEFINE lfolio            INTEGER,
         lnss              CHAR(11),
         lconsec_reg_lote  INTEGER,
         lsiefore          SMALLINT,
         lsubcuenta        SMALLINT,
         lconse_reg        SMALLINT,
         lmonto_soli_1     DECIMAL(16,6),
         lmonto_soli_2     DECIMAL(16,6),
         lmonto_soli_3     DECIMAL(16,6),
         lperiodo_pago     CHAR(06),
         ldiagnostico      SMALLINT,
         lmonto_actual     DECIMAL(16,6),
         ltipo_movimiento  SMALLINT,
         limp_dis_pesos    DECIMAL(16,6),
         lid_aportante     CHAR(11),
         lacc_viv          DECIMAL(22,6),
         li                SMALLINT 

  LET lacc_viv  = 0

  IF lsubcuenta = 5 THEN
     LET lmonto_soli_2 = 0
     LET lmonto_soli_3 = 0
  END IF

  IF lsubcuenta = 4 THEN
     LET lmonto_soli_3 = 0
  END IF

  --- Obtiene diagnostico y saldo actual por subcuenta y nss
  LET ldiagnostico  = 0
  LET lmonto_actual = 0

  SELECT imp_disponible, diagnostico 
    INTO lmonto_actual, ldiagnostico
    FROM safre_tmp:exc_devpgo_sdo
   WHERE folio     = lfolio
     AND nss       = lnss
     AND subcuenta = lsubcuenta
     AND conse_reg = lconse_reg 
 
  IF lmonto_soli_1 > 0 THEN

     IF lsubcuenta <> 4 THEN 

        IF lmonto_actual > 0 THEN

           IF lmonto_actual >= lmonto_soli_1 THEN
              LET limp_dis_pesos = lmonto_soli_1
              LET ldiagnostico   = 1
              LET lmonto_actual  = lmonto_actual - lmonto_soli_1
           ELSE
              LET limp_dis_pesos = lmonto_actual
              LET ldiagnostico   = 4 
              LET lmonto_actual  = 0
           END IF

        ELSE
           LET ldiagnostico   = 2
           LET limp_dis_pesos = 0
        END IF
     ELSE
        IF lmonto_actual > 0  THEN
           IF lmonto_actual >= lmonto_soli_2 THEN
              LET limp_dis_pesos = lmonto_soli_1
              LET ldiagnostico   = 1
              LET lmonto_actual  = lmonto_actual - lmonto_soli_2
              LET lacc_viv       = lmonto_soli_2
           ELSE
              FOR li = 1 TO gtot_arr_prec
                IF garr_prec[li].siefore = 11 THEN
                   LET limp_dis_pesos = lmonto_actual * garr_prec[li].precio
                   EXIT FOR
                END IF 
              END FOR 
              LET lacc_viv       = lmonto_actual
              LET ldiagnostico   = 4
              LET lmonto_actual  = 0
           END IF 
        ELSE
           LET ldiagnostico   = 2
           LET lacc_viv       = 0
           LET limp_dis_pesos = 0
        END IF

     END IF

     LET lconse_reg = lconse_reg + 1

     LET ltipo_movimiento = 540
     LET lid_aportante    = "EXC",lperiodo_pago CLIPPED

     CALL insert_exc_devpgo_sdo(lfolio,lnss,lconsec_reg_lote,lconse_reg,
                            ltipo_movimiento,lsiefore,
                            lsubcuenta,lmonto_soli_1,limp_dis_pesos,
                            lmonto_actual,lid_aportante,ldiagnostico,
                            lacc_viv)
       
  END IF

  IF lsubcuenta <> 5 AND lsubcuenta <> 4 THEN
     IF lmonto_soli_2 > 0 THEN
        IF lmonto_actual > 0 THEN

           IF lmonto_actual >= lmonto_soli_2 THEN
              LET limp_dis_pesos = lmonto_soli_2
              LET ldiagnostico   = 1
              LET lmonto_actual  = lmonto_actual - lmonto_soli_2
           ELSE
              LET limp_dis_pesos = lmonto_actual
              LET ldiagnostico   = 4 
              LET lmonto_actual  = 0
           END IF

        ELSE
           LET ldiagnostico   = 2
           LET limp_dis_pesos = 0
        END IF

        LET lconse_reg = lconse_reg + 1

        LET ltipo_movimiento = 545
        LET lid_aportante    = "EXC",lperiodo_pago CLIPPED 

        CALL insert_exc_devpgo_sdo(lfolio,lnss,lconsec_reg_lote,lconse_reg,
                               ltipo_movimiento,lsiefore,
                               lsubcuenta,lmonto_soli_2,limp_dis_pesos,
                               lmonto_actual,lid_aportante,ldiagnostico,
                               lacc_viv)
     END IF
       
  END IF
     
  IF lsubcuenta <> 5 AND lsubcuenta <> 4 THEN
     IF lmonto_soli_3 > 0 THEN
        IF lmonto_actual > 0 THEN

           IF lmonto_actual >= lmonto_soli_3 THEN
              LET limp_dis_pesos = lmonto_soli_3
              LET ldiagnostico   = 1
              LET lmonto_actual  = lmonto_actual - lmonto_soli_3
           ELSE
              LET limp_dis_pesos = lmonto_actual
              LET ldiagnostico   = 4 
              LET lmonto_actual  = 0
           END IF
        ELSE
           LET ldiagnostico   = 2
           LET limp_dis_pesos = 0
        END IF

        LET lconse_reg = lconse_reg + 1

        LET ltipo_movimiento = 545
        LET lid_aportante    = "REN",lperiodo_pago CLIPPED 

        CALL insert_exc_devpgo_sdo(lfolio,lnss,lconsec_reg_lote,lconse_reg,
                               ltipo_movimiento,lsiefore,
                               lsubcuenta,lmonto_soli_3,limp_dis_pesos,
                               lmonto_actual,lid_aportante,ldiagnostico,
                               lacc_viv)

     END IF
       
  END IF

END FUNCTION

FUNCTION obtiene_diagnostico_final(lfolio,lnss,lconsec_reg_lote)
  DEFINE lfolio           INTEGER,
         lnss             CHAR(11), 
         lconsec_reg_lote INTEGER,
         ldiagnostico     SMALLINT,
         lexis_suficnte   INTEGER 

  LET ldiagnostico = 0

  SELECT MAX(diagnostico) INTO ldiagnostico
    FROM safre_tmp:exc_devpgo_sdo
   WHERE folio      = lfolio
     AND nss        = lnss
     AND conse_lote = lconsec_reg_lote

  IF ldiagnostico IS NULL THEN
     LET ldiagnostico = 0
  END IF

  IF ldiagnostico = 0 THEN
     LET ldiagnostico = 2
  END IF

  IF ldiagnostico = 2 THEN
     ---Valida que en una de las subcuentas no este como suficiente (1)  
     ---de lo contrario el diagnostico queda como parcial (4)

     LET lexis_suficnte = 0

     SELECT COUNT(*) INTO lexis_suficnte 
       FROM safre_tmp:exc_devpgo_sdo
      WHERE folio       = lfolio
        AND nss         = lnss
        AND conse_lote  = lconsec_reg_lote
        AND diagnostico = 1

     IF lexis_suficnte IS NULL THEN
        LET lexis_suficnte = 0
     END IF

     IF lexis_suficnte >= 1 THEN
        LET ldiagnostico = 4
     END IF

  END IF

  RETURN ldiagnostico

END FUNCTION 

FUNCTION insert_exc_devpgo_sdo(lfolio,lnss,lconsec_reg_lote,lconse_reg,
                           ltipo_movimiento,lsiefore,
                           lsubcuenta,lmonto_solici,limp_dis_pesos,
                           lmonto_actual,lid_aportante,ldiagnostico,
                           lacciones)
  DEFINE lfolio            INTEGER,
         lnss              CHAR(11),
         lconsec_reg_lote  INTEGER,
         lconse_reg        SMALLINT,
         ltipo_movimiento  SMALLINT,
         lsiefore          SMALLINT,
         lsubcuenta        SMALLINT,
         lmonto_solici     DECIMAL(16,6),
         limp_dis_pesos    DECIMAL(16,6),
         lmonto_actual     DECIMAL(16,6),
         lid_aportante     CHAR(11),
         ldiagnostico      SMALLINT,
         li                SMALLINT,
         lprecio           DECIMAL(19,6),
         lacciones         DECIMAL(22,6)

  FOR li = 1 TO gtot_arr_prec
    IF garr_prec[li].siefore = lsiefore THEN
       LET lprecio   = garr_prec[li].precio
       EXIT FOR
    END IF 
  END FOR 

  IF lsiefore <> 11 THEN
     LET lacciones = limp_dis_pesos / lprecio 
  END IF
   
  INSERT INTO safre_tmp:exc_devpgo_sdo 
          VALUES (lfolio,
                  lconsec_reg_lote,
                  lconse_reg,
                  ltipo_movimiento,           
                  lsubcuenta,
                  lsiefore,                  
                  lnss,
                  lmonto_solici,
                  limp_dis_pesos,          
                  lacciones,
                  lmonto_actual,
                  lprecio,
                  lid_aportante,           
                  ldiagnostico)
END FUNCTION

#*********************************************************************
FUNCTION actualiza_reg(lfolio, lnss, lconsec_reg_lote, lres_op, 
                       ltipo_rech, lmarca_entra) 
  DEFINE lfolio            INTEGER,
         lnss              CHAR(11),
         lconsec_reg_lote  INTEGER, 
         lres_op           SMALLINT,
         ltipo_rech        CHAR(03),
         lmarca_entra      SMALLINT,
         ldiag_devolucion  CHAR(02)
         
  LET ldiag_devolucion = '02'  #Rechazado 
  CALL des_marca_cuenta(lfolio,lnss,lmarca_entra,lconsec_reg_lote)

  UPDATE exc_det_devpgo
     SET diag_devolucion   = ldiag_devolucion, 
         motivo_devolucion = ltipo_rech  
   WHERE folio           = lfolio 
     AND nss             = lnss
     AND consec_reg_lote = lconsec_reg_lote

END FUNCTION
#*********************************************************************

FUNCTION marca_sufi_parci(lfolio,lnss,lmarca_entra,lres_op,lconsec_reg_lote,
                          lclave_ent_orig)
  DEFINE lfolio               INTEGER,
         lnss                 CHAR(11),
         lmarca_entra         SMALLINT,  
         lres_op              SMALLINT,
         lconsec_reg_lote     INTEGER,  
         lclave_ent_orig      CHAR(03),
         lveces               SMALLINT,
         lconse_marca         DECIMAL(11,0),
         lejecuta             CHAR(250),
         ltipo_rech           CHAR(03),
         lcodigo_rechazo      SMALLINT,
         lcodigo_marca        SMALLINT,
         l_resp               CHAR(02),
         lmarca_estado        SMALLINT,
         ldiag_devolucion     CHAR(02),
         lusuario             CHAR(08)

  LET lmarca_estado   = 0
  LET lcodigo_rechazo = 0 

  LET lveces = 0

  SELECT COUNT(*), USER INTO lveces, lusuario 
    FROM cta_act_marca
   WHERE nss         = lnss
     AND marca_cod   = lmarca_entra 

  IF lveces IS NULL THEN 
     LET lveces = 0
  END IF

  IF lveces = 0 THEN

     LET lejecuta = "EXECUTE PROCEDURE marca_cuenta (?,?,?,?,?,?,?)"
     PREPARE eje_marca FROM lejecuta
     DECLARE cur_marca CURSOR FOR eje_marca
     OPEN cur_marca USING lfolio,
                          lconsec_reg_lote,   ---No se requiere lconse_marca,
                          lnss,
                          lmarca_entra,
                          lmarca_estado,
                          lcodigo_rechazo,
                          lusuario
       FETCH cur_marca INTO lcodigo_marca, lcodigo_rechazo  
 
     CLOSE cur_marca

     IF lcodigo_marca <> lmarca_entra OR lcodigo_rechazo <> 0 THEN
        LET lres_op = 2
        LET lcodigo_rechazo = 382

        CALL actualiza_reg(lfolio,lnss,lconsec_reg_lote, 
                           lres_op,lcodigo_rechazo,lmarca_entra) 
        RETURN
     END IF      

  END IF

  ---  Se actualiza diagnostico devoluacion aceptado y parciales
  CASE lres_op 
    WHEN 1 LET ldiag_devolucion = '01'      
    WHEN 4 LET ldiag_devolucion = '04'
  END CASE 
         
  UPDATE exc_det_devpgo
     SET diag_devolucion   = ldiag_devolucion, 
         motivo_devolucion = NULL
   WHERE folio           = lfolio
     AND consec_reg_lote = lconsec_reg_lote
     AND nss             = lnss
     
END FUNCTION

FUNCTION convivencia(lnss,lmarca_entra)
  DEFINE lnss            CHAR(11),
         lmarca_entra    SMALLINT,
         lcodigo_rechazo SMALLINT  

  LET lcodigo_rechazo = 0

  DECLARE cur_convi_mca CURSOR FOR
  SELECT c.rechazo_cod
    FROM cta_convivencia c, cta_act_marca a
   WHERE c.marca_entra  = lmarca_entra
     AND c.convive_cod  > 0
     AND a.nss          = lnss
     AND c.marca_activa = a.marca_cod
  FOREACH cur_convi_mca INTO lcodigo_rechazo
    EXIT FOREACH
  END FOREACH  

  RETURN lcodigo_rechazo

END FUNCTION

FUNCTION des_marca_cuenta(lfolio,lnss,lmarca_entra,lconsec_reg_lote)
  DEFINE lfolio              INTEGER,
         lnss                CHAR(11),
         lmarca_entra        SMALLINT,  
         lconsec_reg_lote    INTEGER,  
         lveces              SMALLINT,
         lusuario            CHAR(08),
         lmarca_cod          SMALLINT,
         lrechazo_cod        SMALLINT

  #Se utiliza para aquellas cuentas que en carga o en respuesta hayan sido
  #aceptadas y que por generar nuevo diagnostico quedan rechazadas o pendientes

  LET lveces = 0

  SELECT COUNT(*), USER INTO lveces, lusuario 
    FROM cta_act_marca
   WHERE nss         = lnss
     AND marca_cod   = lmarca_entra 

  IF lveces IS NULL THEN 
     LET lveces = 0
  END IF

  IF lveces >= 1 THEN
     CALL des_marca(lfolio,
                    lconsec_reg_lote,
                    lnss,
                    lmarca_entra,
                    lusuario ) RETURNING lmarca_cod, lrechazo_cod
  END IF

END FUNCTION

FUNCTION des_marca(x_folio,
                   x_consecutivo,
                   x_nss,
                   x_marca_entra,
                   x_usuario )

   DEFINE x_folio           INTEGER,
          x_consecutivo     INTEGER,
          x_nss             CHAR(11),
          x_operacion       CHAR(1),
          x_marca_entra     SMALLINT,
          x_marca_estado    SMALLINT,
          x_codigo_rechazo  SMALLINT,
          x_usuario         CHAR(8),
          xx_codigo_marca   SMALLINT,
          xx_codigo_rechazo SMALLINT,
          ejecuta_procedure CHAR(200)

   LET ejecuta_procedure = "EXECUTE PROCEDURE desmarca_cuenta (?,?,?,?,?)"

   LET ejecuta_procedure = ejecuta_procedure CLIPPED

   PREPARE clausula_sql21 FROM ejecuta_procedure

   DECLARE cursor_desmarca1 CURSOR FOR clausula_sql21

   OPEN cursor_desmarca1 USING x_folio,
                              x_consecutivo,
                              x_nss,
                              x_marca_entra,
                              x_usuario

   FETCH cursor_desmarca1 INTO xx_codigo_marca,xx_codigo_rechazo

   CLOSE cursor_desmarca1

   RETURN xx_codigo_marca,xx_codigo_rechazo

END FUNCTION
