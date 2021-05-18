! AeroBulk / 2019 / L. Brodeau
!
!   When using AeroBulk to produce scientific work, please acknowledge with the following citation:
!
!   Brodeau, L., B. Barnier, S. Gulev, and C. Woods, 2016: Climatologically
!   significant effects of some approximations in the bulk parameterizations of
!   turbulent air-sea fluxes. J. Phys. Oceanogr., doi:10.1175/JPO-D-16-0169.1.
!
!
MODULE mod_blk_coare3p6_ij
   !!====================================================================================
   !!       Computes turbulent components of surface fluxes
   !!         according to Fairall et al. 2018 (COARE v3.6)
   !!         "THE TOGA-COARE BULK AIR-SEA FLUX ALGORITHM"
   !!
   !!       With Cool-Skin and Warm-Layer correction of SST (if needed)
   !!
   !!   * bulk transfer coefficients C_D, C_E and C_H
   !!   * air temp. and spec. hum. adjusted from zt (usually 2m) to zu (usually 10m) if needed
   !!   * the "effective" bulk wind speed at zu: Ubzu (including gustiness contribution in unstable conditions)
   !!   => all these are used in bulk formulas in sbcblk.F90
   !!
   !!       Routine turb_coare3p6_ij maintained and developed in AeroBulk
   !!                     (https://github.com/brodeau/aerobulk/)
   !!
   !!            Author: Laurent Brodeau, July 2019
   !!
   !!====================================================================================
   USE mod_const       !: physical and othe constants
   USE mod_phymbl      !: thermodynamics
   USE mod_skin_coare_ij  !: cool-skin parameterization

   IMPLICIT NONE
   PRIVATE

   PUBLIC :: COARE3P6_INIT, TURB_COARE3P6_IJ

   !! COARE own values for given constants:
   REAL(wp), PARAMETER :: zi0   = 600._wp     ! scale height of the atmospheric boundary layer...
   REAL(wp), PARAMETER :: Beta0 =  1.2_wp     ! gustiness parameter
   REAL(wp), PARAMETER :: zeta_abs_max = 50._wp
   !!----------------------------------------------------------------------
CONTAINS


   SUBROUTINE coare3p6_init(l_use_cs, l_use_wl)
      !!---------------------------------------------------------------------
      !!                  ***  FUNCTION coare3p6_init  ***
      !!
      !! INPUT :
      !! -------
      !!    * l_use_cs : use the cool-skin parameterization
      !!    * l_use_wl : use the warm-layer parameterization
      !!---------------------------------------------------------------------
      LOGICAL , INTENT(in) ::   l_use_cs ! use the cool-skin parameterization
      LOGICAL , INTENT(in) ::   l_use_wl ! use the warm-layer parameterization
      INTEGER :: ierr
      !!---------------------------------------------------------------------
      IF( l_use_wl ) THEN
         ierr = 0
         ALLOCATE ( Tau_ac(jpi,jpj) , Qnt_ac(jpi,jpj), dT_wl(jpi,jpj), Hz_wl(jpi,jpj), STAT=ierr )
         IF( ierr > 0 ) CALL ctl_stop( ' COARE3P6_INIT => allocation of Tau_ac, Qnt_ac, dT_wl & Hz_wl failed!' )
         Tau_ac(:,:) = 0._wp
         Qnt_ac(:,:) = 0._wp
         dT_wl(:,:)  = 0._wp
         Hz_wl(:,:)  = Hwl_max
      ENDIF
      IF( l_use_cs ) THEN
         ierr = 0
         ALLOCATE ( dT_cs(jpi,jpj), STAT=ierr )
         IF( ierr > 0 ) CALL ctl_stop( ' COARE3P6_INIT => allocation of dT_cs failed!' )
         dT_cs(:,:) = -0.25_wp  ! First guess of skin correction
      ENDIF
   END SUBROUTINE coare3p6_init



   SUBROUTINE turb_coare3p6_ij( kt, zt, zu, T_s, t_zt, q_s, q_zt, U_zu, l_use_cs, l_use_wl, &
      &                      Cd, Ch, Ce, t_zu, q_zu, Ubzu,                                 &
      &                      Qsw, rad_lw, slp, pdT_cs,                                   & ! optionals for cool-skin (and warm-layer)
      &                      isecday_utc, plong, pdT_wl, pHz_wl,                         & ! optionals for warm-layer only
      &                      CdN, ChN, CeN, xz0, xu_star, xL, xUN10 )
      !!----------------------------------------------------------------------
      !!                      ***  ROUTINE  turb_coare3p6_ij  ***
      !!
      !! ** Purpose :   Computes turbulent transfert coefficients of surface
      !!                fluxes according to Fairall et al. (2003)
      !!                If relevant (zt /= zu), adjust temperature and humidity from height zt to zu
      !!                Returns the effective bulk wind speed at zu to be used in the bulk formulas
      !!
      !!                Applies the cool-skin warm-layer correction of the SST to T_s
      !!                if the net shortwave flux at the surface (Qsw), the downwelling longwave
      !!                radiative fluxes at the surface (rad_lw), and the sea-leve pressure (slp)
      !!                are provided as (optional) arguments!
      !!
      !! INPUT :
      !! -------
      !!    *  kt   : current time step (starts at 1)
      !!    *  zt   : height for temperature and spec. hum. of air            [m]
      !!    *  zu   : height for wind speed (usually 10m)                     [m]
      !!    *  t_zt : potential air temperature at zt                         [K]
      !!    *  q_zt : specific humidity of air at zt                          [kg/kg]
      !!    *  U_zu : scalar wind speed at zu                                 [m/s]
      !!    * l_use_cs : use the cool-skin parameterization
      !!    * l_use_wl : use the warm-layer parameterization
      !!
      !! INPUT/OUTPUT:
      !! -------------
      !!    *  T_s  : always "bulk SST" as input                              [K]
      !!              -> unchanged "bulk SST" as output if CSWL not used      [K]
      !!              -> skin temperature as output if CSWL used              [K]
      !!
      !!    *  q_s  : SSQ aka saturation specific humidity at temp. T_s       [kg/kg]
      !!              -> doesn't need to be given a value if skin temp computed (in case l_use_cs=True or l_use_wl=True)
      !!              -> MUST be given the correct value if not computing skint temp. (in case l_use_cs=False or l_use_wl=False)
      !!
      !! OPTIONAL INPUT:
      !! ---------------
      !!    *  Qsw    : net solar flux (after albedo) at the surface (>0)     [W/m^2]
      !!    *  rad_lw : downwelling longwave radiation at the surface  (>0)   [W/m^2]
      !!    *  slp    : sea-level pressure                                    [Pa]
      !!    * isecday_utc:
      !!    *  plong  : longitude array                                       [deg.E]
      !!
      !! OPTIONAL OUTPUT:
      !! ----------------
      !!    * pdT_cs  : SST increment "dT" for cool-skin correction           [K]
      !!    * pdT_wl  : SST increment "dT" for warm-layer correction          [K]
      !!    * pHz_wl  : thickness of warm-layer                               [m]
      !!
      !! OUTPUT :
      !! --------
      !!    *  Cd     : drag coefficient
      !!    *  Ch     : sensible heat coefficient
      !!    *  Ce     : evaporation coefficient
      !!    *  t_zu   : pot. air temperature adjusted at wind height zu       [K]
      !!    *  q_zu   : specific humidity of air        //                    [kg/kg]
      !!    *  Ubzu  : bulk wind speed at zu                                 [m/s]
      !!
      !! OPTIONAL OUTPUT:
      !! ----------------
      !!    * CdN      : neutral-stability drag coefficient
      !!    * ChN      : neutral-stability sensible heat coefficient
      !!    * CeN      : neutral-stability evaporation coefficient
      !!    * xz0      : return the aerodynamic roughness length (integration constant for wind stress) [m]
      !!    * xu_star  : return u* the friction velocity                    [m/s]
      !!    * xL       : return the Obukhov length                          [m]
      !!    * xUN10    : neutral wind speed at 10m                          [m/s]
      !!
      !! ** Author: L. Brodeau, June 2019 / AeroBulk (https://github.com/brodeau/aerobulk/)
      !!----------------------------------------------------------------------------------
      INTEGER,  INTENT(in   )                     ::   kt       ! current time step
      REAL(wp), INTENT(in   )                     ::   zt       ! height for t_zt and q_zt                    [m]
      REAL(wp), INTENT(in   )                     ::   zu       ! height for U_zu                             [m]
      REAL(wp), INTENT(inout), DIMENSION(jpi,jpj) ::   T_s      ! sea surface temperature                [Kelvin]
      REAL(wp), INTENT(in   ), DIMENSION(jpi,jpj) ::   t_zt     ! potential air temperature              [Kelvin]
      REAL(wp), INTENT(inout), DIMENSION(jpi,jpj) ::   q_s      ! sea surface specific humidity           [kg/kg]
      REAL(wp), INTENT(in   ), DIMENSION(jpi,jpj) ::   q_zt     ! specific air humidity at zt             [kg/kg]
      REAL(wp), INTENT(in   ), DIMENSION(jpi,jpj) ::   U_zu     ! relative wind module at zu                [m/s]
      LOGICAL , INTENT(in   )                     ::   l_use_cs ! use the cool-skin parameterization
      LOGICAL , INTENT(in   )                     ::   l_use_wl ! use the warm-layer parameterization
      REAL(wp), INTENT(  out), DIMENSION(jpi,jpj) ::   Cd       ! transfer coefficient for momentum         (tau)
      REAL(wp), INTENT(  out), DIMENSION(jpi,jpj) ::   Ch       ! transfer coefficient for sensible heat (Q_sens)
      REAL(wp), INTENT(  out), DIMENSION(jpi,jpj) ::   Ce       ! transfert coefficient for evaporation   (Q_lat)
      REAL(wp), INTENT(  out), DIMENSION(jpi,jpj) ::   t_zu     ! pot. air temp. adjusted at zu               [K]
      REAL(wp), INTENT(  out), DIMENSION(jpi,jpj) ::   q_zu     ! spec. humidity adjusted at zu           [kg/kg]
      REAL(wp), INTENT(  out), DIMENSION(jpi,jpj) ::   Ubzu    ! bulk wind speed at zu                     [m/s]
      !
      REAL(wp), INTENT(in   ), OPTIONAL, DIMENSION(jpi,jpj) ::   Qsw      !             [W/m^2]
      REAL(wp), INTENT(in   ), OPTIONAL, DIMENSION(jpi,jpj) ::   rad_lw   !             [W/m^2]
      REAL(wp), INTENT(in   ), OPTIONAL, DIMENSION(jpi,jpj) ::   slp      !             [Pa]
      REAL(wp), INTENT(  out), OPTIONAL, DIMENSION(jpi,jpj) ::   pdT_cs
      !
      INTEGER,  INTENT(in   ), OPTIONAL                     ::   isecday_utc ! current UTC time, counted in second since 00h of the current day
      REAL(wp), INTENT(in   ), OPTIONAL, DIMENSION(jpi,jpj) ::   plong    !             [deg.E]
      REAL(wp), INTENT(  out), OPTIONAL, DIMENSION(jpi,jpj) ::   pdT_wl   !             [K]
      REAL(wp), INTENT(  out), OPTIONAL, DIMENSION(jpi,jpj) ::   pHz_wl   !             [m]
      !
      REAL(wp), INTENT(  out), OPTIONAL, DIMENSION(jpi,jpj) ::   CdN
      REAL(wp), INTENT(  out), OPTIONAL, DIMENSION(jpi,jpj) ::   ChN
      REAL(wp), INTENT(  out), OPTIONAL, DIMENSION(jpi,jpj) ::   CeN
      REAL(wp), INTENT(  out), OPTIONAL, DIMENSION(jpi,jpj) ::   xz0  ! Aerodynamic roughness length   [m]
      REAL(wp), INTENT(  out), OPTIONAL, DIMENSION(jpi,jpj) ::   xu_star  ! u*, friction velocity
      REAL(wp), INTENT(  out), OPTIONAL, DIMENSION(jpi,jpj) ::   xL  ! zeta (zu/L)
      REAL(wp), INTENT(  out), OPTIONAL, DIMENSION(jpi,jpj) ::   xUN10  ! Neutral wind at zu
      !
      INTEGER :: ji, jj, jit
      LOGICAL :: l_zt_equal_zu = .FALSE.      ! if q and t are given at same height as U
      !
      !REAL(wp), DIMENSION(:,:), ALLOCATABLE  ::  &
      !   &  u_star, t_star, q_star, &
      !   &  dt_zu, dq_zu,    &
      !   &  znu_a,           & !: Nu_air, Viscosity of air
      !   &  z0, z0t
      !REAL(wp), DIMENSION(:,:), ALLOCATABLE :: zeta_u        ! stability parameter at height zu
      !REAL(wp), DIMENSION(:,:), ALLOCATABLE :: zeta_t        ! stability parameter at height zt
      !REAL(wp), DIMENSION(:,:), ALLOCATABLE :: ztmp0, ztmp1, ztmp2
      !
      REAL(wp), DIMENSION(:,:), ALLOCATABLE :: zSST     ! to back up the initial bulk SST
      !
      REAL(wp) :: zdt, zdq, zus, zts, zqs, zNu_a, zRib, z1oL, zpsi_m_u, zpsi_h_u, zpsi_h_t, zdT_cs, zgust2
      REAL(wp) :: zz0, zz0t, zz0q, zprof_m, zprof_h, zpsi_h_z0t, zpsi_h_z0q, zzeta_u, zzeta_t
      REAL(wp) :: ztmp0, ztmp1, ztmp2
      REAL(wp) :: zlog_z0, zlog_zu, zlog_zt_o_zu
      !
      LOGICAL ::  lreturn_cdn=.FALSE., lreturn_chn=.FALSE., lreturn_cen=.FALSE., &
         &        lreturn_z0=.FALSE., lreturn_ustar=.FALSE., lreturn_L=.FALSE., lreturn_UN10=.FALSE.
      CHARACTER(len=40), PARAMETER :: crtnm = 'turb_coare3p6_ij@mod_blk_coare3p6_ij.f90'
      !!----------------------------------------------------------------------------------

      IF( kt == nit000 ) CALL COARE3P6_INIT(l_use_cs, l_use_wl)

      lreturn_cdn   =  PRESENT(CdN)
      lreturn_chn   =  PRESENT(ChN)
      lreturn_cen   =  PRESENT(CeN)
      lreturn_z0    =  PRESENT(xz0)
      lreturn_ustar =  PRESENT(xu_star)
      lreturn_L     =  PRESENT(xL)
      lreturn_UN10  =  PRESENT(xUN10)

      l_zt_equal_zu = ( ABS(zu - zt) < 0.01_wp )

      !! Initializations for cool skin and warm layer:
      IF( l_use_cs .AND. (.NOT.(PRESENT(Qsw) .AND. PRESENT(rad_lw) .AND. PRESENT(slp))) ) &
         &   CALL ctl_stop( '['//TRIM(crtnm)//'] => ' , 'you need to provide Qsw, rad_lw & slp to use cool-skin param!' )

      IF( l_use_wl .AND. (.NOT.(PRESENT(Qsw) .AND. PRESENT(rad_lw) .AND. PRESENT(slp)     &
         &  .AND. PRESENT(isecday_utc) .AND. PRESENT(plong)) ) ) &
         &   CALL ctl_stop( '['//TRIM(crtnm)//'] => ' , 'you need to provide Qsw, rad_lw, slp, isecday_utc', &
         &   ' & plong to use warm-layer param!'  )

      IF( l_use_cs .OR. l_use_wl ) THEN
         ALLOCATE ( zSST(jpi,jpj) )
         zSST = T_s ! backing up the bulk SST
         IF( l_use_cs ) T_s = T_s - 0.25_wp   ! First guess of correction
         q_s    = rdct_qsat_salt*q_sat(MAX(T_s, 200._wp), slp) ! First guess of q_s
      ENDIF

      !ALLOCATE ( zu_star(jpi,jpj), zt_star(jpi,jpj), zq_star(jpi,jpj) )

      !! Constants:
      zlog_zu      = LOG(zu)
      zlog_zt_o_zu = LOG(zt/zu)


      CALL FIRST_GUESS_COARE( zt, zu, T_s, t_zt, q_s, q_zt, U_zu, charn_coare3p6(U_zu),  &
         &                    zu_star, zt_star, zq_star, t_zu, q_zu, Ubzu )
      PRINT *, ''
      PRINT *, 'LOLO: apres FIRST_GUESS_COARE turb_ecmwf_ij: zu_star =', zu_star
      !+ check t_zu and q_zu !!! LOLO


      DO jj = 1, jpj
         DO ji = 1, jpi

            !! Pot. temp. difference (and we don't want it to be 0!)
            zdt = t_zu(ji,jj) - T_s(ji,jj) ;   zdt = SIGN( MAX(ABS(zdt),1.E-6_wp), zdt )
            zdq = q_zu(ji,jj) - q_s(ji,jj) ;   zdq = SIGN( MAX(ABS(zdq),1.E-9_wp), zdq )


            !! ITERATION BLOCK
            DO jit = 1, nb_iter

               !!Inverse of Obukov length (1/L) :
               ztmp0 = One_on_L(t_zu, q_zu, u_star, t_star, q_star)  ! 1/L == 1/[Obukhov length]
               ztmp0 = SIGN( MIN(ABS(ztmp0),200._wp), ztmp0 ) ! 1/L (prevents FPE from stupid values from masked region later on...)

               ztmp1 = u_star*u_star   ! u*^2

               !! Update wind at zu with convection-related wind gustiness in unstable conditions (Fairall et al. 2003, Eq.8):
               ztmp2 = Beta0*Beta0*ztmp1*(MAX(-zi0*ztmp0/vkarmn,0._wp))**(2._wp/3._wp) ! square of wind gustiness contribution, ztmp2 == Ug^2
               !!   ! Only true when unstable (L<0) => when ztmp0 < 0 => explains "-" before zi0
               Ubzu = MAX(SQRT(U_zu*U_zu + ztmp2), 0.2_wp)        ! include gustiness in bulk wind speed
               ! => 0.2 prevents Ubzu to be 0 in stable case when U_zu=0.

               !! Stability parameters:
               zeta_u = zu*ztmp0
               zeta_u = SIGN( MIN(ABS(zeta_u),zeta_abs_max), zeta_u )
               IF( .NOT. l_zt_equal_zu ) THEN
                  zeta_t = zt*ztmp0
                  zeta_t = SIGN( MIN(ABS(zeta_t),zeta_abs_max), zeta_t )
               ENDIF

               !! Adjustment the wind at 10m (not needed in the current algo form):
               !IF( zu \= 10._wp ) U10 = U_zu + u_star/vkarmn*(LOG(10._wp/zu) - psi_m_coare_sclr(10._wp*ztmp0) + psi_m_coare_sclr(zeta_u))

               !! Roughness lengthes z0, z0t (z0q = z0t) :
               ztmp2 = u_star/vkarmn*LOG(10./z0)                                 ! Neutral wind speed at 10m
               z0    = charn_coare3p6(ztmp2)*ztmp1/grav + 0.11_wp*znu_a/u_star   ! Roughness length (eq.6) [ ztmp1==u*^2 ]
               z0     = MIN( MAX(ABS(z0), 1.E-9) , 1._wp )                      ! (prevents FPE from stupid values from masked region later on)

               ztmp1 = ( znu_a / (z0*u_star) )**0.72_wp     ! COARE3.6-specific! (1./Re_r)^0.72 (Re_r: roughness Reynolds number) COARE3.6-specific!
               z0t   = MIN( 1.6E-4_wp , 5.8E-5_wp*ztmp1 )   ! COARE3.6-specific!
               z0t   = MIN( MAX(ABS(z0t), 1.E-9) , 1._wp )                      ! (prevents FPE from stupid values from masked region later on)

               !! Turbulent scales at zu :
               ztmp0   = psi_h_coare_sclr(zeta_u)
               ztmp1   = vkarmn/(LOG(zu) - LOG(z0t) - ztmp0) ! #LB: in ztmp0, some use psi_h_coare_sclr(zeta_t) rather than psi_h_coare_sclr(zeta_t) ???

               t_star = dt_zu*ztmp1
               q_star = dq_zu*ztmp1
               u_star = MAX( Ubzu*vkarmn/(LOG(zu) - LOG(z0) - psi_m_coare_sclr(zeta_u)) , 1.E-9 )  !  (MAX => prevents FPE from stupid values from masked region later on)

               IF( .NOT. l_zt_equal_zu ) THEN
                  !! Re-updating temperature and humidity at zu if zt /= zu :
                  ztmp1 = LOG(zt/zu) + ztmp0 - psi_h_coare_sclr(zeta_t)
                  t_zu = t_zt - t_star/vkarmn*ztmp1
                  q_zu = q_zt - q_star/vkarmn*ztmp1
               ENDIF

               IF( l_use_cs ) THEN
                  !! Cool-skin contribution

                  CALL UPDATE_QNSOL_TAU( zu, T_s, q_s, t_zu, q_zu, u_star, t_star, q_star, U_zu, Ubzu, slp, rad_lw, &
                     &                   ztmp1, zeta_u,  Qlat=ztmp2)  ! Qnsol -> ztmp1 / Tau -> zeta_u

                  CALL CS_COARE( Qsw, ztmp1, u_star, zSST, ztmp2 )  ! ! Qnsol -> ztmp1 / Qlat -> ztmp2

                  T_s(:,:) = zSST(:,:) + dT_cs(:,:)
                  IF( l_use_wl ) T_s(:,:) = T_s(:,:) + dT_wl(:,:)
                  q_s(:,:) = rdct_qsat_salt*q_sat(MAX(T_s(:,:), 200._wp), slp(:,:))
               ENDIF

               IF( l_use_wl ) THEN
                  !! Warm-layer contribution
                  CALL UPDATE_QNSOL_TAU( zu, T_s, q_s, t_zu, q_zu, u_star, t_star, q_star, U_zu, Ubzu, slp, rad_lw, &
                     &                   ztmp1, zeta_u)  ! Qnsol -> ztmp1 / Tau -> zeta_u
                  !! In WL_COARE or , Tau_ac and Qnt_ac must be updated at the final itteration step => add a flag to do this!
                  CALL WL_COARE( Qsw, ztmp1, zeta_u, zSST, plong, isecday_utc, MOD(nb_iter,jit) )

                  !! Updating T_s and q_s !!!
                  T_s(:,:) = zSST(:,:) + dT_wl(:,:)
                  IF( l_use_cs ) T_s(:,:) = T_s(:,:) + dT_cs(:,:)
                  q_s(:,:) = rdct_qsat_salt*q_sat(MAX(T_s(:,:), 200._wp), slp(:,:))
               ENDIF

               IF( l_use_cs .OR. l_use_wl .OR. (.NOT. l_zt_equal_zu) ) THEN
                  dt_zu = t_zu - T_s ;  dt_zu = SIGN( MAX(ABS(dt_zu),1.E-6_wp), dt_zu )
                  dq_zu = q_zu - q_s ;  dq_zu = SIGN( MAX(ABS(dq_zu),1.E-9_wp), dq_zu )
               ENDIF

            END DO !DO jit = 1, nb_iter

            ! compute transfer coefficients at zu :
            ztmp0 = u_star/Ubzu
            Cd   = MAX( ztmp0*ztmp0        , Cx_min )
            Ch   = MAX( ztmp0*t_star/dt_zu , Cx_min )
            Ce   = MAX( ztmp0*q_star/dq_zu , Cx_min )


         END DO
      END DO


      IF( lreturn_cdn .OR. lreturn_chn .OR. lreturn_cen ) ztmp0 = 1._wp/LOG(zu/z0)
      IF( lreturn_cdn )   CdN = MAX( vkarmn2*ztmp0*ztmp0       , Cx_min )
      IF( lreturn_chn )   ChN = MAX( vkarmn2*ztmp0/LOG(zu/z0t) , Cx_min )
      IF( lreturn_cen )   CeN = MAX( vkarmn2*ztmp0/LOG(zu/z0t) , Cx_min )

      IF( lreturn_z0 )    xz0     = z0
      IF( lreturn_ustar ) xu_star = u_star
      IF( lreturn_L )     xL      = 1./One_on_L(t_zu, q_zu, u_star, t_star, q_star)
      IF( lreturn_UN10 )  xUN10   = u_star/vkarmn*LOG(10./z0)

      DEALLOCATE ( u_star, t_star, q_star, zeta_u, dt_zu, dq_zu, z0, z0t, znu_a, ztmp0, ztmp1, ztmp2 )
      IF( .NOT. l_zt_equal_zu ) DEALLOCATE( zeta_t )

      IF( l_use_cs .AND. PRESENT(pdT_cs) ) pdT_cs = dT_cs
      IF( l_use_wl .AND. PRESENT(pdT_wl) ) pdT_wl = dT_wl
      IF( l_use_wl .AND. PRESENT(pHz_wl) ) pHz_wl = Hz_wl

      IF( l_use_cs .OR. l_use_wl ) DEALLOCATE ( zSST )

   END SUBROUTINE turb_coare3p6_ij


   FUNCTION charn_coare3p6( pwnd )
      !!-------------------------------------------------------------------
      !! Computes the Charnock parameter as a function of the Neutral wind speed at 10m
      !!  "wind speed dependent formulation"
      !!  (Eq. 13 in Edson et al., 2013)
      !!
      !! Author: L. Brodeau, July 2019 / AeroBulk  (https://github.com/brodeau/aerobulk/)
      !!-------------------------------------------------------------------
      REAL(wp), DIMENSION(jpi,jpj) :: charn_coare3p6
      REAL(wp), DIMENSION(jpi,jpj), INTENT(in) :: pwnd   ! neutral wind speed at 10m
      !
      REAL(wp), PARAMETER :: charn0_max = 0.028  !: value above which the Charnock parameter levels off for winds > 18 m/s
      !!-------------------------------------------------------------------
      charn_coare3p6 = MAX( MIN( 0.0017_wp*pwnd - 0.005_wp , charn0_max) , 0._wp )
      !!
   END FUNCTION charn_coare3p6

   FUNCTION charn_coare3p6_wave( pus, pwsh, pwps )
      !!-------------------------------------------------------------------
      !! Computes the Charnock parameter as a function of wave information and u*
      !!
      !!  (COARE 3.6, Fairall et al., 2018)
      !!
      !! Author: L. Brodeau, October 2019 / AeroBulk  (https://github.com/brodeau/aerobulk/)
      !!-------------------------------------------------------------------
      REAL(wp), DIMENSION(jpi,jpj) :: charn_coare3p6_wave
      REAL(wp), DIMENSION(jpi,jpj), INTENT(in) :: pus   ! friction velocity             [m/s]
      REAL(wp), DIMENSION(jpi,jpj), INTENT(in) :: pwsh  ! significant wave height       [m]
      REAL(wp), DIMENSION(jpi,jpj), INTENT(in) :: pwps  ! phase speed of dominant waves [m/s]
      !!-------------------------------------------------------------------
      charn_coare3p6_wave = ( pwsh*0.2_wp*(pus/pwps)**2.2_wp ) * grav/(pus*pus)
      !!
   END FUNCTION charn_coare3p6_wave

   !!======================================================================
END MODULE mod_blk_coare3p6_ij
