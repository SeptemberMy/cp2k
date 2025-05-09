!--------------------------------------------------------------------------------------------------!
!   CP2K: A general program to perform molecular dynamics simulations                              !
!   Copyright 2000-2025 CP2K developers group <https://cp2k.org>                                   !
!                                                                                                  !
!   SPDX-License-Identifier: GPL-2.0-or-later                                                      !
!--------------------------------------------------------------------------------------------------!

! **************************************************************************************************
!> \brief calculate the Hamprecht, Cohen, Tozer, and Handy (HCTH) exchange
!>      functional
!> \author fawzi
! **************************************************************************************************
MODULE xc_hcth

   USE cp_log_handling,                 ONLY: cp_to_string
   USE kinds,                           ONLY: dp
   USE mathconstants,                   ONLY: pi
   USE xc_derivative_desc,              ONLY: deriv_norm_drho,&
                                              deriv_rho
   USE xc_derivative_set_types,         ONLY: xc_derivative_set_type,&
                                              xc_dset_get_derivative
   USE xc_derivative_types,             ONLY: xc_derivative_get,&
                                              xc_derivative_type
   USE xc_rho_cflags_types,             ONLY: xc_rho_cflags_type
   USE xc_rho_set_types,                ONLY: xc_rho_set_get,&
                                              xc_rho_set_type
#include "../base/base_uses.f90"

   IMPLICIT NONE
   PRIVATE

   LOGICAL, PRIVATE, PARAMETER :: debug_this_module = .TRUE.
   CHARACTER(len=*), PARAMETER, PRIVATE :: moduleN = 'xc_hcth'

   PUBLIC :: hcth_lda_info, hcth_lda_eval
CONTAINS

! **************************************************************************************************
!> \brief return various information on the functional
!> \param iparset ...
!> \param reference string with the reference of the actual functional
!> \param shortform string with the shortform of the functional name
!> \param needs the components needed by this functional are set to
!>        true (does not set the unneeded components to false)
!> \param max_deriv ...
!> \author fawzi
! **************************************************************************************************
   SUBROUTINE hcth_lda_info(iparset, reference, shortform, needs, max_deriv)
      INTEGER, INTENT(in)                                :: iparset
      CHARACTER(LEN=*), INTENT(OUT), OPTIONAL            :: reference, shortform
      TYPE(xc_rho_cflags_type), INTENT(inout), OPTIONAL  :: needs
      INTEGER, INTENT(out), OPTIONAL                     :: max_deriv

      SELECT CASE (iparset)
      CASE (93)
         IF (PRESENT(reference)) THEN
            reference = "F. A. Hamprecht, A. J. Cohen, D. J. Tozer, and N. C. Handy, J. Chem. Phys. 109, 6264 (1998);"// &
                        " HCTH/93 xc functional {LDA version}"
         END IF
         IF (PRESENT(shortform)) THEN
            shortform = "HCTH/93 xc energy functional (LDA)"
         END IF
      CASE (120)
         IF (PRESENT(reference)) THEN
            reference = "A. D. Boese, N. L. Doltsinis, N. C. Handy, and M. Sprik, J. Chem. Phys. 112, 1670 (2000);"// &
                        " HCTH/120 xc functional {LDA version}"
         END IF
         IF (PRESENT(shortform)) THEN
            shortform = "HCTH/120 xc energy functional (LDA)"
         END IF
      CASE (147)
         IF (PRESENT(reference)) THEN
            reference = "A. D. Boese, N. L. Doltsinis, N. C. Handy, and M. Sprik, J. Chem. Phys. 112, 1670 (2000);"// &
                        " HCTH/147 xc functional {LDA Version}"
         END IF
         IF (PRESENT(shortform)) THEN
            shortform = "HCTH/147 xc energy functional (LDA)"
         END IF
      CASE (407)
         IF (PRESENT(reference)) THEN
            reference = "A. D. Boese and N. C. Handy, J. Chem. Phys. 114, 5497 (2001); "// &
                        "HCTH/407 xc functional {LDA version}"
         END IF
         IF (PRESENT(shortform)) THEN
            shortform = "HCTH/407 xc energy functional (LDA)"
         END IF
      CASE (408)
         IF (PRESENT(reference)) THEN
            reference = "P. Verma and D. G. Truhlar, J. Phys. Chem. Lett. 8, 380 (2016); "// &
                        "HLE16 xc functional {LDA version}"
         END IF
         IF (PRESENT(shortform)) THEN
            shortform = "HLE16 xc energy functional (LDA)"
         END IF
      CASE default
         CPABORT("Invalid HCTH parameter set requested ("//cp_to_string(iparset)//")")
      END SELECT
      IF (PRESENT(needs)) THEN
         needs%rho = .TRUE.
         needs%norm_drho = .TRUE.
      END IF
      IF (PRESENT(max_deriv)) max_deriv = 1

   END SUBROUTINE hcth_lda_info

! **************************************************************************************************
!> \brief evaluates the hcth functional for lda
!> \param iparset the parameter set that should be used (93,120,147,407)
!> \param rho_set the density where you want to evaluate the functional
!> \param deriv_set place where to store the functional derivatives (they are
!>        added to the derivatives)
!> \param grad_deriv degree of the derivative that should be evaluated,
!>        if positive all the derivatives up to the given degree are evaluated,
!>        if negative only the given degree is calculated
!> \author fawzi
! **************************************************************************************************
   SUBROUTINE hcth_lda_eval(iparset, rho_set, deriv_set, grad_deriv)
      INTEGER, INTENT(in)                                :: iparset
      TYPE(xc_rho_set_type), INTENT(IN)                  :: rho_set
      TYPE(xc_derivative_set_type), INTENT(IN)           :: deriv_set
      INTEGER, INTENT(in)                                :: grad_deriv

      INTEGER                                            :: npoints
      INTEGER, DIMENSION(2, 3)                           :: bo
      REAL(kind=dp)                                      :: epsilon_rho
      REAL(kind=dp), CONTIGUOUS, DIMENSION(:, :, :), &
         POINTER                                         :: e_0, e_ndrho, e_rho, norm_drho, rho
      TYPE(xc_derivative_type), POINTER                  :: deriv

      NULLIFY (e_0, e_ndrho, e_rho, norm_drho, rho)

      CALL xc_rho_set_get(rho_set, rho=rho, &
                          norm_drho=norm_drho, local_bounds=bo, rho_cutoff=epsilon_rho)
      npoints = (bo(2, 1) - bo(1, 1) + 1)*(bo(2, 2) - bo(1, 2) + 1)*(bo(2, 3) - bo(1, 3) + 1)

      IF (grad_deriv >= 0) THEN
         deriv => xc_dset_get_derivative(deriv_set, [INTEGER::], &
                                         allocate_deriv=.TRUE.)
         CALL xc_derivative_get(deriv, deriv_data=e_0)
      END IF
      deriv => xc_dset_get_derivative(deriv_set, [deriv_rho], &
                                      allocate_deriv=.TRUE.)
      CALL xc_derivative_get(deriv, deriv_data=e_rho)
      deriv => xc_dset_get_derivative(deriv_set, [deriv_norm_drho], &
                                      allocate_deriv=.TRUE.)
      CALL xc_derivative_get(deriv, deriv_data=e_ndrho)
      IF (grad_deriv > 1 .OR. grad_deriv < -1) THEN
         CPABORT("derivatives bigger than 1 not implemented")
      END IF

      CALL hcth_lda_calc(iparset=iparset, rho=rho, norm_drho=norm_drho, &
                         e_0=e_0, e_rho=e_rho, e_ndrho=e_ndrho, &
                         npoints=npoints, epsilon_rho=epsilon_rho)
   END SUBROUTINE hcth_lda_eval

! **************************************************************************************************
!> \brief Calculate the gradient-corrected xc energy and potential
!>      of Hamprecht, Cohen, Tozer, and Handy (HCTH) for a closed shell
!>      density.
!> \param iparset the parameter set that should be used (93,120,147,407)
!> \param rho the density
!> \param norm_drho the norm of the gradient of the density
!> \param e_0 the value of the functional in that point
!> \param e_rho the derivative of the functional wrt. rho
!> \param e_ndrho the derivative of the functional wrt. norm_drho
!> \param epsilon_rho the cutoff on rho
!> \param npoints ...
!> \author fawzi (copying from the routine of Matthias Krack in functionals.F)
!> \note
!>     Literature:- F. A. Hamprecht, A. J. Cohen, D. J. Tozer, and N. C. Handy,
!>                  J. Chem. Phys. 109, 6264 (1998) -> HCTH/93
!>                - A. D. Boese, N. L. Doltsinis, N. C. Handy, and M. Sprik,
!>                  J. Chem. Phys. 112, 1670 (2000) -> HCTH/120 and HCTH/147
!>                - A. D. Boese and N. C. Handy,
!>                  J. Chem. Phys. 114, 5497 (2001) -> HCTH/407
!>                - J. P. Perdew and Y. Wang,
!>                  Phys. Rev. B 45, 13244 (1992) -> PW92
! **************************************************************************************************
   SUBROUTINE hcth_lda_calc(iparset, rho, norm_drho, e_0, e_rho, e_ndrho, &
                            epsilon_rho, npoints)
      INTEGER, INTENT(IN)                                :: iparset
      REAL(KIND=dp), DIMENSION(*), INTENT(IN)            :: rho, norm_drho
      REAL(KIND=dp), DIMENSION(*), INTENT(INOUT)         :: e_0, e_rho, e_ndrho
      REAL(kind=dp), INTENT(in)                          :: epsilon_rho
      INTEGER, INTENT(IN)                                :: npoints

      REAL(KIND=dp), DIMENSION(4), PARAMETER :: &
         beta0 = (/7.59570_dp, 3.58760_dp, 1.63820_dp, 0.49294_dp/), &
         beta1 = (/14.11890_dp, 6.19770_dp, 3.36620_dp, 0.62517_dp/)
      REAL(KIND=dp), PARAMETER :: a0 = 0.031091_dp, a1 = 0.015545_dp, alpha0 = 0.21370_dp, &
         alpha1 = 0.20548_dp, f13 = 1.0_dp/3.0_dp, f43 = 4.0_dp*f13, f83 = 8.0_dp*f13, &
         gamma_cab = 0.006_dp, gamma_css = 0.200_dp, gamma_xss = 0.004_dp

      INTEGER                                            :: ii
      REAL(KIND=dp) :: cx_vwn_e, cx_vwn_v, dgcabddrho, dgcabdrho, dgcabds, dgcssddrho, dgcssdrho, &
         dgcssds, dgdrs, dgxssddrho, dgxssdrho, dgxssds, drho, drhos, drsdrho, ecab, ecss, exss, &
         g, gcab, gcss, gs2, gxss, my_rho, p, q, rho13, rho43, rhos, rhos13, rhos43, rs, rs12, &
         rsfac, s, s2, two13, u, vcab, vcss, vxss, x, y
      REAL(KIND=dp), DIMENSION(0:4)                      :: ccab, ccss, cxss

      cx_vwn_e = -0.75_dp*(3.0_dp/pi)**f13
      cx_vwn_v = f43*cx_vwn_e
      rsfac = (f43*pi)**(-f13)
      two13 = 2.0_dp**f13

      !   *** LSDA correlation parametrisation (PW92) ***
      !   *** GGA parametrisation (HCTH/iparset) ***

      !     *** Load the HCTH parameter set HCTH/iparset ***

      SELECT CASE (iparset)
      CASE (93)
         cxss(0) = 0.109320E+01_dp
         ccss(0) = 0.222601E+00_dp
         ccab(0) = 0.729974E+00_dp
         cxss(1) = -0.744056E+00_dp
         ccss(1) = -0.338622E-01_dp
         ccab(1) = 0.335287E+01_dp
         cxss(2) = 0.559920E+01_dp
         ccss(2) = -0.125170E-01_dp
         ccab(2) = -0.115430E+02_dp
         cxss(3) = -0.678549E+01_dp
         ccss(3) = -0.802496E+00_dp
         ccab(3) = 0.808564E+01_dp
         cxss(4) = 0.449357E+01_dp
         ccss(4) = 0.155396E+01_dp
         ccab(4) = -0.447857E+01_dp
      CASE (120)
         cxss(0) = 0.109163E+01_dp
         ccss(0) = 0.489508E+00_dp
         ccab(0) = 0.514730E+00_dp
         cxss(1) = -0.747215E+00_dp
         ccss(1) = -0.260699E+00_dp
         ccab(1) = 0.692982E+01_dp
         cxss(2) = 0.507833E+01_dp
         ccss(2) = 0.432917E+00_dp
         ccab(2) = -0.247073E+02_dp
         cxss(3) = -0.410746E+01_dp
         ccss(3) = -0.199247E+01_dp
         ccab(3) = 0.231098E+02_dp
         cxss(4) = 0.117173E+01_dp
         ccss(4) = 0.248531E+01_dp
         ccab(4) = -0.113234E+02_dp
      CASE (147)
         cxss(0) = 0.109025E+01_dp
         ccss(0) = 0.562576E+00_dp
         ccab(0) = 0.542352E+00_dp
         cxss(1) = -0.799194E+00_dp
         ccss(1) = 0.171436E-01_dp
         ccab(1) = 0.701464E+01_dp
         cxss(2) = 0.557212E+01_dp
         ccss(2) = -0.130636E+01_dp
         ccab(2) = -0.283822E+02_dp
         cxss(3) = -0.586760E+01_dp
         ccss(3) = 0.105747E+01_dp
         ccab(3) = 0.350329E+02_dp
         cxss(4) = 0.304544E+01_dp
         ccss(4) = 0.885429E+00_dp
         ccab(4) = -0.204284E+02_dp
      CASE (407)
         cxss(0) = 0.108184E+01_dp
         ccss(0) = 0.118777E+01_dp
         ccab(0) = 0.589076E+00_dp
         cxss(1) = -0.518339E+00_dp
         ccss(1) = -0.240292E+01_dp
         ccab(1) = 0.442374E+01_dp
         cxss(2) = 0.342562E+01_dp
         ccss(2) = 0.561741E+01_dp
         ccab(2) = -0.192218E+02_dp
         cxss(3) = -0.262901E+01_dp
         ccss(3) = -0.917923E+01_dp
         ccab(3) = 0.425721E+02_dp
         cxss(4) = 0.228855E+01_dp
         ccss(4) = 0.624798E+01_dp
         ccab(4) = -0.420052E+02_dp
!           DMB all-in-one HLE16 and applying 5/4 scaling
!           to all exchange terms and 1/2 to all correlation terms
      CASE (408)
         cxss(0) = 0.108184E+01_dp*1.25_dp
         ccss(0) = 0.118777E+01_dp*0.5_dp
         ccab(0) = 0.589076E+00_dp*0.5_dp
         cxss(1) = -0.518339E+00_dp*1.25_dp
         ccss(1) = -0.240292E+01_dp*0.5_dp
         ccab(1) = 0.442374E+01_dp*0.5_dp
         cxss(2) = 0.342562E+01_dp*1.25_dp
         ccss(2) = 0.561741E+01_dp*0.5_dp
         ccab(2) = -0.192218E+02_dp*0.5_dp
         cxss(3) = -0.262901E+01_dp*1.25_dp
         ccss(3) = -0.917923E+01_dp*0.5_dp
         ccab(3) = 0.425721E+02_dp*0.5_dp
         cxss(4) = 0.228855E+01_dp*1.25_dp
         ccss(4) = 0.624798E+01_dp*0.5_dp
         ccab(4) = -0.420052E+02_dp*0.5_dp
      CASE DEFAULT
         CPABORT("Invalid HCTH parameter set requested ("//cp_to_string(iparset)//")")
      END SELECT

!$OMP     PARALLEL DO DEFAULT(NONE) SHARED(rho,norm_drho,cxss,ccss,&
!$OMP             ccab,cx_vwn_e, cx_vwn_v, rsfac, two13,epsilon_rho,npoints, &
!$OMP             e_0,e_rho,e_ndrho)&
!$OMP           PRIVATE(ii, dgcabddrho, dgcabdrho, dgcabds, dgcssddrho, &
!$OMP             dgcssdrho, dgcssds, dgdrs, dgxssddrho, dgxssdrho, dgxssds,&
!$OMP             drhos, drsdrho, ecab, ecss, exss, g, gcab, gcss, gs2, &
!$OMP             gxss, p, q, rho13, rho43, rhos, rhos13, rhos43, rs, rs12,&
!$OMP             s, s2, u, vcab, vcss, vxss, x, y, my_rho, drho)
      DO ii = 1, npoints
         !     *** rho_sigma = rho/2 = rho_alpha = rho_beta (same for |nabla rho|) ***

         IF (rho(ii) > epsilon_rho) THEN
            my_rho = MAX(rho(ii), epsilon_rho)
            drho = norm_drho(ii)
            rhos = 0.5_dp*my_rho
            drhos = 0.5_dp*drho

            rhos13 = rhos**f13
            rhos43 = rhos13*rhos

            rho13 = two13*rhos13
            rho43 = rho13*my_rho

            !     *** LSDA exchange part (VWN) ***

            exss = cx_vwn_e*rho43
            vxss = cx_vwn_v*rho13

            !     *** LSDA correlation part (PW92) ***

            !     *** G(rho_sigma,0) => spin polarisation zeta = 1 ***

            rs = rsfac/rhos13
            rs12 = SQRT(rs)
            q = 2.0_dp*a1*(beta1(1) + (beta1(2) + (beta1(3) + &
                                                   beta1(4)*rs12)*rs12)*rs12)*rs12
            p = 1.0_dp + 1.0_dp/q
            x = -2.0_dp*a1*(1.0_dp + alpha1*rs)
            y = LOG(p)
            g = x*y
            dgdrs = -2.0_dp*a1*alpha1*y - &
                    x*a1*(beta1(1)/rs12 + 2.0_dp*beta1(2) + &
                          3.0_dp*beta1(3)*rs12 + 4.0_dp*beta1(4)*rs)/(p*q*q)
            drsdrho = -f13*rs/my_rho
            ecss = my_rho*g
            vcss = g + my_rho*dgdrs*drsdrho

            !     *** G(rho_alpha,rho_beta) => spin polarisation zeta = 0 ***

            rs = rsfac/rho13
            rs12 = SQRT(rs)
            q = 2.0_dp*a0*(beta0(1) + (beta0(2) + (beta0(3) + &
                                                   beta0(4)*rs12)*rs12)*rs12)*rs12
            p = 1.0_dp + 1.0_dp/q
            x = -2.0_dp*a0*(1.0_dp + alpha0*rs)
            y = LOG(p)
            g = x*y
            dgdrs = -2.0_dp*a0*alpha0*y - &
                    x*a0*(beta0(1)/rs12 + 2.0_dp*beta0(2) + &
                          3.0_dp*beta0(3)*rs12 + 4.0_dp*beta0(4)*rs)/(p*q*q)
            drsdrho = -f13*rs/my_rho
            ecab = my_rho*g - ecss
            vcab = g + my_rho*dgdrs*drsdrho - vcss

            !     *** GGA part (HCTH) ***

            s = drhos/rhos43
            s2 = s*s
            x = -f83/my_rho
            y = 2.0_dp/(drho*drho)

            !     *** g_x(rho_sigma,rho_sigma) ***

            gs2 = gamma_xss*s2
            q = 1.0_dp/(1.0_dp + gs2)
            u = gs2*q
            gxss = cxss(0) + (cxss(1) + (cxss(2) + (cxss(3) + cxss(4)*u)*u)*u)*u
            dgxssds = q*(cxss(1) + (2.0_dp*cxss(2) + (3.0_dp*cxss(3) + &
                                                      4.0_dp*cxss(4)*u)*u)*u)*u
            dgxssdrho = x*dgxssds
            dgxssddrho = y*dgxssds

            !     *** g_c(rho_sigma,rho_sigma) ***

            gs2 = gamma_css*s2
            q = 1.0_dp/(1.0_dp + gs2)
            u = gs2*q
            gcss = ccss(0) + (ccss(1) + (ccss(2) + (ccss(3) + ccss(4)*u)*u)*u)*u
            dgcssds = q*(ccss(1) + (2.0_dp*ccss(2) + (3.0_dp*ccss(3) + &
                                                      4.0_dp*ccss(4)*u)*u)*u)*u
            dgcssdrho = x*dgcssds
            dgcssddrho = y*dgcssds

            !     *** g_c(rho_alpha,rho_beta) ***

            gs2 = gamma_cab*s2
            q = 1.0_dp/(1.0_dp + gs2)
            u = gs2*q
            gcab = ccab(0) + (ccab(1) + (ccab(2) + (ccab(3) + ccab(4)*u)*u)*u)*u
            dgcabds = q*(ccab(1) + (2.0_dp*ccab(2) + (3.0_dp*ccab(3) + &
                                                      4.0_dp*ccab(4)*u)*u)*u)*u
            dgcabdrho = x*dgcabds
            dgcabddrho = y*dgcabds

            !     *** Finally collect all contributions ***

            e_0(ii) = e_0(ii) + exss*gxss + ecss*gcss + ecab*gcab
            e_rho(ii) = e_rho(ii) + vxss*gxss + exss*dgxssdrho + &
                        vcss*gcss + ecss*dgcssdrho + &
                        vcab*gcab + ecab*dgcabdrho
            e_ndrho(ii) = e_ndrho(ii) + (exss*dgxssddrho + ecss*dgcssddrho + ecab*dgcabddrho)*drho
         END IF
      END DO

   END SUBROUTINE hcth_lda_calc

END MODULE xc_hcth
