!--------------------------------------------------------------------------------------------------!
!   CP2K: A general program to perform molecular dynamics simulations                              !
!   Copyright 2000-2025 CP2K developers group <https://cp2k.org>                                   !
!                                                                                                  !
!   SPDX-License-Identifier: GPL-2.0-or-later                                                      !
!--------------------------------------------------------------------------------------------------!

! **************************************************************************************************
!> \brief Contains utilities for a Dimer Method calculations
!> \par History
!>      none
!> \author Luca Bellucci and Teodoro Laino - created [tlaino] - 01.2008
! **************************************************************************************************
MODULE dimer_utils
   USE cp_log_handling,                 ONLY: cp_logger_get_default_io_unit
   USE dimer_types,                     ONLY: dimer_env_type
   USE input_section_types,             ONLY: section_vals_get_subs_vals,&
                                              section_vals_remove_values,&
                                              section_vals_type,&
                                              section_vals_val_set
   USE kinds,                           ONLY: dp
   USE memory_utilities,                ONLY: reallocate
#include "../base/base_uses.f90"

   IMPLICIT NONE
   PRIVATE

   LOGICAL, PRIVATE, PARAMETER :: debug_this_module = .TRUE.
   CHARACTER(len=*), PARAMETER, PRIVATE :: moduleN = 'dimer_utils'

   PUBLIC :: rotate_dimer, update_dimer_vec, get_theta
   REAL(KIND=dp), PARAMETER, PUBLIC     :: dimer_thrs = EPSILON(0.0_dp)*1.0E4_dp

CONTAINS

! **************************************************************************************************
!> \brief Performs a rotation of the unit dimer vector
!> \param nvec ...
!> \param theta ...
!> \param dt ...
!> \par History
!>      none
!> \author Luca Bellucci and Teodoro Laino - created [tlaino] - 01.2008
! **************************************************************************************************
   SUBROUTINE rotate_dimer(nvec, theta, dt)
      REAL(KIND=dp), DIMENSION(:), POINTER               :: nvec, theta
      REAL(KIND=dp)                                      :: dt

      INTEGER                                            :: output_unit
      LOGICAL                                            :: check

      output_unit = cp_logger_get_default_io_unit()

      ! Orthogonality check for the rotation..
      check = ABS(DOT_PRODUCT(nvec, theta)) < MAX(1.0E-9_dp, dimer_thrs)
      IF (.NOT. check .AND. (output_unit > 0)) THEN
         WRITE (output_unit, *) "NVEC and THETA should be orthogonal! Residue: ", &
            ABS(DOT_PRODUCT(nvec, theta))
      END IF
      CPASSERT(check)
      nvec = nvec*COS(dt) + theta*SIN(dt)

   END SUBROUTINE rotate_dimer

! **************************************************************************************************
!> \brief Updates the orientation of the dimer vector in the input file
!> \param dimer_env ...
!> \param motion_section ...
!> \par History
!>      none
!> \author Luca Bellucci and Teodoro Laino - created [tlaino] - 01.2008
! **************************************************************************************************
   SUBROUTINE update_dimer_vec(dimer_env, motion_section)
      TYPE(dimer_env_type), POINTER                      :: dimer_env
      TYPE(section_vals_type), POINTER                   :: motion_section

      INTEGER                                            :: i, i_rep_val, isize, j, size_array
      REAL(KIND=dp), DIMENSION(:), POINTER               :: array
      TYPE(section_vals_type), POINTER                   :: nvec_section

      nvec_section => section_vals_get_subs_vals(motion_section, &
                                                 "GEO_OPT%TRANSITION_STATE%DIMER%DIMER_VECTOR")
      ! Clean the content of the section first..
      CALL section_vals_remove_values(nvec_section)
      ! Fill in the section with the present values..
      size_array = 6
      isize = 0
      i_rep_val = 0
      Main_Loop: DO i = 1, SIZE(dimer_env%nvec), size_array
         ALLOCATE (array(size_array))
         i_rep_val = i_rep_val + 1
         DO j = 1, size_array
            isize = isize + 1
            array(j) = dimer_env%nvec(isize)
            IF (isize == SIZE(dimer_env%nvec)) THEN
               CALL reallocate(array, 1, j)
               CALL section_vals_val_set(nvec_section, "_DEFAULT_KEYWORD_", r_vals_ptr=array, &
                                         i_rep_val=i_rep_val)
               EXIT Main_Loop
            END IF
         END DO
         CALL section_vals_val_set(nvec_section, "_DEFAULT_KEYWORD_", r_vals_ptr=array, &
                                   i_rep_val=i_rep_val)
      END DO Main_Loop
      CPASSERT(isize == SIZE(dimer_env%nvec))
   END SUBROUTINE update_dimer_vec

! **************************************************************************************************
!> \brief This function orthonormalize the vector for the rotational search
!> \param gradient ...
!> \param dimer_env ...
!> \param norm ...
!> \par History
!>      none
!> \author Luca Bellucci and Teodoro Laino - created [tlaino] - 01.2008
! **************************************************************************************************
   SUBROUTINE get_theta(gradient, dimer_env, norm)
      REAL(KIND=dp), DIMENSION(:)                        :: gradient
      TYPE(dimer_env_type), POINTER                      :: dimer_env
      REAL(KIND=dp), INTENT(OUT)                         :: norm

      gradient = gradient - DOT_PRODUCT(gradient, dimer_env%nvec)*dimer_env%nvec
      norm = SQRT(DOT_PRODUCT(gradient, gradient))
      IF (norm < EPSILON(0.0_dp)) THEN
         ! This means that NVEC is totally aligned with minimum curvature mode
         gradient = 0.0_dp
      ELSE
         gradient = gradient/norm
      END IF
   END SUBROUTINE get_theta

END MODULE dimer_utils
