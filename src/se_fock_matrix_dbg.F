!--------------------------------------------------------------------------------------------------!
!   CP2K: A general program to perform molecular dynamics simulations                              !
!   Copyright 2000-2025 CP2K developers group <https://cp2k.org>                                   !
!                                                                                                  !
!   SPDX-License-Identifier: GPL-2.0-or-later                                                      !
!--------------------------------------------------------------------------------------------------!

MODULE se_fock_matrix_dbg
   USE cp_dbcsr_api,                    ONLY: dbcsr_p_type,&
                                              dbcsr_set
   USE cp_dbcsr_contrib,                ONLY: dbcsr_dot
   USE kinds,                           ONLY: dp
   USE qs_energy_types,                 ONLY: init_qs_energy,&
                                              qs_energy_type
   USE qs_environment_types,            ONLY: qs_environment_type
   USE se_fock_matrix_coulomb,          ONLY: build_fock_matrix_coulomb_lr
   USE semi_empirical_store_int_types,  ONLY: semi_empirical_si_type
#include "./base/base_uses.f90"

   IMPLICIT NONE
   PRIVATE

   CHARACTER(len=*), PARAMETER, PRIVATE :: moduleN = 'se_fock_matrix_dbg'
   LOGICAL, PARAMETER, PRIVATE          :: debug_this_module = .FALSE.

   PUBLIC :: dbg_energy_coulomb_lr

CONTAINS

! **************************************************************************************************
!> \brief Debug routine for long-range energy (debug value of EWALD vs VALUE KS)
!> \param energy ...
!> \param ks_matrix ...
!> \param nspins ...
!> \param qs_env ...
!> \param matrix_p ...
!> \param calculate_forces ...
!> \param store_int_env ...
!> \author Teodoro Laino [tlaino] - 04.2009
! **************************************************************************************************
   SUBROUTINE dbg_energy_coulomb_lr(energy, ks_matrix, nspins, qs_env, matrix_p, &
                                    calculate_forces, store_int_env)
      TYPE(qs_energy_type), POINTER                      :: energy
      TYPE(dbcsr_p_type), DIMENSION(:), POINTER          :: ks_matrix
      INTEGER, INTENT(IN)                                :: nspins
      TYPE(qs_environment_type), POINTER                 :: qs_env
      TYPE(dbcsr_p_type), DIMENSION(:), POINTER          :: matrix_p
      LOGICAL, INTENT(IN)                                :: calculate_forces
      TYPE(semi_empirical_si_type), POINTER              :: store_int_env

      INTEGER                                            :: ispin
      REAL(KIND=dp)                                      :: ecoul

! Zero structures only for debugging purpose

      CALL init_qs_energy(energy)
      DO ispin = 1, nspins
         CALL dbcsr_set(ks_matrix(ispin)%matrix, 0.0_dp)
      END DO

      ! Evaluate Coulomb Long-Range
      CALL build_fock_matrix_coulomb_lr(qs_env, ks_matrix, matrix_p, energy, calculate_forces, &
                                        store_int_env)

      ! Compute the Hartree energy
      DO ispin = 1, nspins
         CALL dbcsr_dot(ks_matrix(ispin)%matrix, matrix_p(ispin)%matrix, ecoul)
         energy%hartree = energy%hartree + ecoul

         WRITE (*, *) ispin, "ECOUL ", ecoul
      END DO
      WRITE (*, *) "ENUC in DBG:", energy%core_overlap

      ! Debug statements
      WRITE (*, *) "TOTAL ENE", 0.5_dp*energy%hartree + energy%core_overlap
      CPABORT("Debug energy for Coulomb Long-Range")

   END SUBROUTINE dbg_energy_coulomb_lr

END MODULE se_fock_matrix_dbg
