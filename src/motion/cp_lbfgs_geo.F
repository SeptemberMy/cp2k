!--------------------------------------------------------------------------------------------------!
!   CP2K: A general program to perform molecular dynamics simulations                              !
!   Copyright 2000-2025 CP2K developers group <https://cp2k.org>                                   !
!                                                                                                  !
!   SPDX-License-Identifier: GPL-2.0-or-later                                                      !
!--------------------------------------------------------------------------------------------------!

! **************************************************************************************************
!> \brief Main driver for L-BFGS optimizer
!> \par History
!>      01.2020 Space Group Symmetry introduced by Pierre-André Cazade [pcazade]
! **************************************************************************************************
MODULE cp_lbfgs_geo
   USE cell_types,                      ONLY: cell_type
   USE cp_external_control,             ONLY: external_control
   USE cp_lbfgs_optimizer_gopt,         ONLY: cp_lbfgs_opt_gopt_type,&
                                              cp_opt_gopt_create,&
                                              cp_opt_gopt_next,&
                                              cp_opt_gopt_release,&
                                              cp_opt_gopt_stop
   USE cp_log_handling,                 ONLY: cp_get_default_logger,&
                                              cp_logger_type
   USE cp_output_handling,              ONLY: cp_iterate,&
                                              cp_print_key_finished_output,&
                                              cp_print_key_unit_nr
   USE cp_subsys_types,                 ONLY: cp_subsys_type
   USE force_env_types,                 ONLY: force_env_get,&
                                              force_env_type
   USE global_types,                    ONLY: global_environment_type
   USE gopt_f_methods,                  ONLY: gopt_f_ii,&
                                              gopt_f_io_finalize,&
                                              print_geo_opt_header,&
                                              print_geo_opt_nc
   USE gopt_f_types,                    ONLY: gopt_f_type
   USE gopt_param_types,                ONLY: gopt_param_type
   USE input_constants,                 ONLY: default_ts_method_id
   USE input_section_types,             ONLY: section_vals_type,&
                                              section_vals_val_get,&
                                              section_vals_val_set
   USE kinds,                           ONLY: dp
   USE message_passing,                 ONLY: mp_para_env_type
   USE space_groups,                    ONLY: identify_space_group,&
                                              print_spgr,&
                                              spgr_apply_rotations_coord
   USE space_groups_types,              ONLY: spgr_type
#include "../base/base_uses.f90"

   IMPLICIT NONE
   PRIVATE

   CHARACTER(len=*), PARAMETER, PRIVATE :: moduleN = 'cp_lbfgs_geo'

   PUBLIC :: geoopt_lbfgs

CONTAINS

! **************************************************************************************************
!> \brief ...
!> \param force_env ...
!> \param gopt_param ...
!> \param globenv ...
!> \param geo_section ...
!> \param gopt_env ...
!> \param x0 ...
!> \par History
!>      08.2003 created [fawzi]
!>      01.2020 modified [pcazade]
!> \author Fawzi Mohamed
! **************************************************************************************************
   SUBROUTINE geoopt_lbfgs(force_env, gopt_param, globenv, geo_section, gopt_env, &
                           x0)
      TYPE(force_env_type), POINTER                      :: force_env
      TYPE(gopt_param_type), POINTER                     :: gopt_param
      TYPE(global_environment_type), POINTER             :: globenv
      TYPE(section_vals_type), POINTER                   :: geo_section
      TYPE(gopt_f_type), POINTER                         :: gopt_env
      REAL(KIND=dp), DIMENSION(:), POINTER               :: x0

      CHARACTER(len=*), PARAMETER                        :: routineN = 'geoopt_lbfgs'

      INTEGER                                            :: handle, iter_nr, its, output_unit
      LOGICAL                                            :: converged, should_stop
      REAL(KIND=dp)                                      :: trust_radius
      TYPE(cell_type), POINTER                           :: cell
      TYPE(cp_lbfgs_opt_gopt_type), POINTER              :: optimizer
      TYPE(cp_logger_type), POINTER                      :: logger
      TYPE(cp_subsys_type), POINTER                      :: subsys
      TYPE(mp_para_env_type), POINTER                    :: para_env
      TYPE(section_vals_type), POINTER                   :: root_section
      TYPE(spgr_type), POINTER                           :: spgr

      CALL timeset(routineN, handle)

      NULLIFY (optimizer, para_env, spgr)
      logger => cp_get_default_logger()
      spgr => gopt_env%spgr
      root_section => force_env%root_section
      CPASSERT(ASSOCIATED(force_env))
      CPASSERT(ASSOCIATED(gopt_param))

      ! collecting subsys
      CALL force_env_get(force_env, para_env=para_env, cell=cell, subsys=subsys)

      ! Geometry optimization starts now
      output_unit = cp_print_key_unit_nr(logger, geo_section, "PRINT%PROGRAM_RUN_INFO", &
                                         extension=".geoLog")
      CALL print_geo_opt_header(gopt_env, output_unit, "L-BFGS")

      ! finds space group
      CALL section_vals_val_get(geo_section, "KEEP_SPACE_GROUP", l_val=spgr%keep_space_group)
      IF (spgr%keep_space_group) THEN
         CALL identify_space_group(subsys, geo_section, gopt_env, output_unit)
         CALL spgr_apply_rotations_coord(spgr, x0)
         CALL print_spgr(spgr)
      END IF

      ! Stop if not implemented
      IF (gopt_env%type_id == default_ts_method_id) &
         CPABORT("BFGS method not yet working with DIMER")

      CALL section_vals_val_get(geo_section, "LBFGS%TRUST_RADIUS", r_val=trust_radius)
      ALLOCATE (optimizer)
      CALL cp_opt_gopt_create(optimizer, para_env=para_env, obj_funct=gopt_env, &
                              x0=x0, wanted_relative_f_delta=gopt_param%wanted_rel_f_error, &
                              wanted_projected_gradient=gopt_param%wanted_proj_gradient, m=gopt_param%max_h_rank, &
                              max_f_per_iter=gopt_param%max_f_per_iter, trust_radius=trust_radius)
      CALL cp_iterate(logger%iter_info, increment=0, iter_nr_out=iter_nr)
      converged = .FALSE.

      DO its = iter_nr + 1, gopt_param%max_iter
         CALL cp_iterate(logger%iter_info, last=(its == gopt_param%max_iter))
         CALL section_vals_val_set(geo_section, "STEP_START_VAL", i_val=its)
         CALL gopt_f_ii(its, output_unit)

         ! Real optimization step..
         IF (.NOT. cp_opt_gopt_next(optimizer, geo_section=geo_section, &
                                    force_env=force_env, gopt_param=gopt_param, &
                                    converged=converged, spgr=spgr)) EXIT

         ! Check for an external exit command
         CALL external_control(should_stop, "GEO", globenv=globenv)
         IF (should_stop) THEN
            CALL cp_opt_gopt_stop(optimizer)
            EXIT
         END IF
         IF (its == gopt_param%max_iter) EXIT
      END DO

      IF ((its == gopt_param%max_iter) .AND. (.NOT. converged)) THEN
         CALL print_geo_opt_nc(gopt_env, output_unit)
      END IF

      ! show space_group
      CALL section_vals_val_get(geo_section, "SHOW_SPACE_GROUP", l_val=spgr%show_space_group)
      IF (spgr%show_space_group) THEN
         CALL identify_space_group(subsys, geo_section, gopt_env, output_unit)
         CALL print_spgr(spgr)
      END IF

      ! Write final output information, if converged
      CALL cp_iterate(logger%iter_info, last=.TRUE., increment=0)
      CALL gopt_f_io_finalize(gopt_env, force_env, optimizer%x, converged, its, root_section, &
                              optimizer%para_env, optimizer%master, output_unit)

      CALL cp_opt_gopt_release(optimizer)
      DEALLOCATE (optimizer)
      CALL cp_print_key_finished_output(output_unit, logger, geo_section, &
                                        "PRINT%PROGRAM_RUN_INFO")

      CALL timestop(handle)

   END SUBROUTINE geoopt_lbfgs

END MODULE cp_lbfgs_geo
