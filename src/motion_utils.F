!--------------------------------------------------------------------------------------------------!
!   CP2K: A general program to perform molecular dynamics simulations                              !
!   Copyright 2000-2025 CP2K developers group <https://cp2k.org>                                   !
!                                                                                                  !
!   SPDX-License-Identifier: GPL-2.0-or-later                                                      !
!--------------------------------------------------------------------------------------------------!

! **************************************************************************************************
!> \brief  Output Utilities for MOTION_SECTION
!> \author Teodoro Laino [tlaino] - University of Zurich
!> \date   02.2008
! **************************************************************************************************
MODULE motion_utils

   USE cell_types,                      ONLY: cell_type
   USE cp2k_info,                       ONLY: compile_revision,&
                                              cp2k_version,&
                                              r_datx,&
                                              r_host_name,&
                                              r_user_name
   USE cp_log_handling,                 ONLY: cp_get_default_logger,&
                                              cp_logger_type
   USE cp_output_handling,              ONLY: cp_print_key_finished_output,&
                                              cp_print_key_unit_nr
   USE cp_subsys_types,                 ONLY: cp_subsys_get,&
                                              cp_subsys_type
   USE cp_units,                        ONLY: cp_unit_from_cp2k
   USE force_env_types,                 ONLY: force_env_get,&
                                              force_env_type
   USE input_constants,                 ONLY: dump_atomic,&
                                              dump_dcd,&
                                              dump_dcd_aligned_cell,&
                                              dump_pdb,&
                                              dump_xmol
   USE input_section_types,             ONLY: section_get_ival,&
                                              section_vals_get,&
                                              section_vals_get_subs_vals,&
                                              section_vals_type,&
                                              section_vals_val_get
   USE kinds,                           ONLY: default_string_length,&
                                              dp,&
                                              sp
   USE machine,                         ONLY: m_flush
   USE mathlib,                         ONLY: diamat_all
   USE particle_list_types,             ONLY: particle_list_type
   USE particle_methods,                ONLY: write_particle_coordinates
   USE particle_types,                  ONLY: particle_type
   USE physcon,                         ONLY: angstrom
   USE virial_types,                    ONLY: virial_type
#include "./base/base_uses.f90"

   IMPLICIT NONE

   PRIVATE

   PUBLIC :: write_trajectory, write_stress_tensor_to_file, write_simulation_cell, &
             get_output_format, rot_ana

   CHARACTER(len=*), PARAMETER, PRIVATE :: moduleN = 'motion_utils'
   REAL(KIND=dp), PARAMETER, PUBLIC     :: thrs_motion = 5.0E-10_dp

CONTAINS

! **************************************************************************************************
!> \brief Performs an analysis of the principal inertia axis
!>      Getting back the generators of the translating and
!>      rotating frame
!> \param particles ...
!> \param mat ...
!> \param dof ...
!> \param print_section ...
!> \param keep_rotations ...
!> \param mass_weighted ...
!> \param natoms ...
!> \param rot_dof ...
!> \param inertia ...
!> \author Teodoro Laino 08.2006
! **************************************************************************************************
   SUBROUTINE rot_ana(particles, mat, dof, print_section, keep_rotations, mass_weighted, &
                      natoms, rot_dof, inertia)
      TYPE(particle_type), DIMENSION(:), POINTER         :: particles
      REAL(KIND=dp), DIMENSION(:, :), OPTIONAL, POINTER  :: mat
      INTEGER, INTENT(OUT)                               :: dof
      TYPE(section_vals_type), POINTER                   :: print_section
      LOGICAL, INTENT(IN)                                :: keep_rotations, mass_weighted
      INTEGER, INTENT(IN)                                :: natoms
      INTEGER, INTENT(OUT), OPTIONAL                     :: rot_dof
      REAL(KIND=dp), INTENT(OUT), OPTIONAL               :: inertia(3)

      CHARACTER(len=*), PARAMETER                        :: routineN = 'rot_ana'

      INTEGER                                            :: handle, i, iparticle, iseq, iw, j, k, &
                                                            lrot(3)
      LOGICAL                                            :: present_mat
      REAL(KIND=dp)                                      :: cp(3), Ip(3, 3), Ip_eigval(3), mass, &
                                                            masst, norm, rcom(3), rm(3)
      REAL(KIND=dp), ALLOCATABLE, DIMENSION(:, :)        :: Rot, Tr
      TYPE(cp_logger_type), POINTER                      :: logger

      CALL timeset(routineN, handle)
      logger => cp_get_default_logger()
      present_mat = PRESENT(mat)
      CPASSERT(ASSOCIATED(particles))
      IF (present_mat) THEN
         CPASSERT(.NOT. ASSOCIATED(mat))
      END IF
      IF (.NOT. keep_rotations) THEN
         rcom = 0.0_dp
         masst = 0.0_dp
         ! Center of mass
         DO iparticle = 1, natoms
            mass = 1.0_dp
            IF (mass_weighted) mass = particles(iparticle)%atomic_kind%mass
            CPASSERT(mass >= 0.0_dp)
            masst = masst + mass
            rcom = particles(iparticle)%r*mass + rcom
         END DO
         CPASSERT(masst > 0.0_dp)
         rcom = rcom/masst
         ! Intertia Tensor
         Ip = 0.0_dp
         DO iparticle = 1, natoms
            mass = 1.0_dp
            IF (mass_weighted) mass = particles(iparticle)%atomic_kind%mass
            rm = particles(iparticle)%r - rcom
            Ip(1, 1) = Ip(1, 1) + mass*(rm(2)**2 + rm(3)**2)
            Ip(2, 2) = Ip(2, 2) + mass*(rm(1)**2 + rm(3)**2)
            Ip(3, 3) = Ip(3, 3) + mass*(rm(1)**2 + rm(2)**2)
            Ip(1, 2) = Ip(1, 2) - mass*(rm(1)*rm(2))
            Ip(1, 3) = Ip(1, 3) - mass*(rm(1)*rm(3))
            Ip(2, 3) = Ip(2, 3) - mass*(rm(2)*rm(3))
         END DO
         ! Diagonalize the Inertia Tensor
         CALL diamat_all(Ip, Ip_eigval)
         IF (PRESENT(inertia)) inertia = Ip_eigval
         iw = cp_print_key_unit_nr(logger, print_section, "ROTATIONAL_INFO", extension=".vibLog")
         IF (iw > 0) THEN
            WRITE (UNIT=iw, FMT='(/,T2,A)') &
               'ROT| Rotational analysis information'
            WRITE (UNIT=iw, FMT='(T2,A)') &
               'ROT| Principal axes and moments of inertia [a.u.]'
            WRITE (UNIT=iw, FMT='(T2,A,T14,3(1X,I19))') &
               'ROT|', 1, 2, 3
            WRITE (UNIT=iw, FMT='(T2,A,T21,3(1X,ES19.11))') &
               'ROT| Eigenvalues', Ip_eigval(1:3)
            WRITE (UNIT=iw, FMT='(T2,A,T21,3(1X,F19.12))') &
               'ROT|      x', Ip(1, 1:3)
            WRITE (UNIT=iw, FMT='(T2,A,T21,3(1X,F19.12))') &
               'ROT|      y', Ip(2, 1:3)
            WRITE (UNIT=iw, FMT='(T2,A,T21,3(1X,F19.12))') &
               'ROT|      z', Ip(3, 1:3)
         END IF
         CALL cp_print_key_finished_output(iw, logger, print_section, "ROTATIONAL_INFO")
         iw = cp_print_key_unit_nr(logger, print_section, "ROTATIONAL_INFO/COORDINATES", extension=".vibLog")
         IF (iw > 0) THEN
            WRITE (UNIT=iw, FMT='(/,T2,A)') 'ROT| Standard molecule orientation in Angstrom'
            DO iparticle = 1, natoms
               WRITE (UNIT=iw, FMT='(T2,"ROT|",T20,A,T27,3(3X,F15.9))') &
                  TRIM(particles(iparticle)%atomic_kind%name), &
                  MATMUL(particles(iparticle)%r, Ip)*angstrom
            END DO
         END IF
         CALL cp_print_key_finished_output(iw, logger, print_section, "ROTATIONAL_INFO/COORDINATES")
      END IF
      ! Build up the Translational vectors
      ALLOCATE (Tr(natoms*3, 3))
      Tr = 0.0_dp
      DO k = 1, 3
         iseq = 0
         DO iparticle = 1, natoms
            mass = 1.0_dp
            IF (mass_weighted) mass = SQRT(particles(iparticle)%atomic_kind%mass)
            DO j = 1, 3
               iseq = iseq + 1
               IF (j == k) Tr(iseq, k) = mass
            END DO
         END DO
      END DO
      ! Normalize Translations
      DO i = 1, 3
         norm = SQRT(DOT_PRODUCT(Tr(:, i), Tr(:, i)))
         Tr(:, i) = Tr(:, i)/norm
      END DO
      dof = 3
      ! Build up the Rotational vectors
      ALLOCATE (Rot(natoms*3, 3))
      lrot = 0
      IF (.NOT. keep_rotations) THEN
         DO iparticle = 1, natoms
            mass = 1.0_dp
            IF (mass_weighted) mass = SQRT(particles(iparticle)%atomic_kind%mass)
            rm = particles(iparticle)%r - rcom
            cp(1) = rm(1)*Ip(1, 1) + rm(2)*Ip(2, 1) + rm(3)*Ip(3, 1)
            cp(2) = rm(1)*Ip(1, 2) + rm(2)*Ip(2, 2) + rm(3)*Ip(3, 2)
            cp(3) = rm(1)*Ip(1, 3) + rm(2)*Ip(2, 3) + rm(3)*Ip(3, 3)
            ! X Rot
            Rot((iparticle - 1)*3 + 1, 1) = (cp(2)*Ip(1, 3) - Ip(1, 2)*cp(3))*mass
            Rot((iparticle - 1)*3 + 2, 1) = (cp(2)*Ip(2, 3) - Ip(2, 2)*cp(3))*mass
            Rot((iparticle - 1)*3 + 3, 1) = (cp(2)*Ip(3, 3) - Ip(3, 2)*cp(3))*mass
            ! Y Rot
            Rot((iparticle - 1)*3 + 1, 2) = (cp(3)*Ip(1, 1) - Ip(1, 3)*cp(1))*mass
            Rot((iparticle - 1)*3 + 2, 2) = (cp(3)*Ip(2, 1) - Ip(2, 3)*cp(1))*mass
            Rot((iparticle - 1)*3 + 3, 2) = (cp(3)*Ip(3, 1) - Ip(3, 3)*cp(1))*mass
            ! Z Rot
            Rot((iparticle - 1)*3 + 1, 3) = (cp(1)*Ip(1, 2) - Ip(1, 1)*cp(2))*mass
            Rot((iparticle - 1)*3 + 2, 3) = (cp(1)*Ip(2, 2) - Ip(2, 1)*cp(2))*mass
            Rot((iparticle - 1)*3 + 3, 3) = (cp(1)*Ip(3, 2) - Ip(3, 1)*cp(2))*mass
         END DO

         ! Normalize Rotations and count the number of degree of freedom
         lrot = 1
         DO i = 1, 3
            norm = DOT_PRODUCT(Rot(:, i), Rot(:, i))
            IF (norm <= thrs_motion) THEN
               lrot(i) = 0
               CYCLE
            END IF
            Rot(:, i) = Rot(:, i)/SQRT(norm)
            ! Clean Rotational modes for spurious/numerical contamination
            IF (i < 3) THEN
               DO j = 1, i
                  Rot(:, i + 1) = Rot(:, i + 1) - DOT_PRODUCT(Rot(:, i + 1), Rot(:, j))*Rot(:, j)
               END DO
            END IF
         END DO
      END IF
      IF (PRESENT(rot_dof)) rot_dof = COUNT(lrot == 1)
      dof = dof + COUNT(lrot == 1)
      iw = cp_print_key_unit_nr(logger, print_section, "ROTATIONAL_INFO", extension=".vibLog")
      IF (iw > 0) THEN
         WRITE (iw, '(T2,A,T71,I10)') 'ROT| Number of rotovibrational vectors', dof
         IF (dof == 5) THEN
            WRITE (iw, '(T2,A)') &
               'ROT| Linear molecule detected'
         END IF
         IF ((dof == 3) .AND. (.NOT. keep_rotations)) THEN
            WRITE (iw, '(T2,A)') &
               'ROT| Single atom detected'
         END IF
      END IF
      CALL cp_print_key_finished_output(iw, logger, print_section, "ROTATIONAL_INFO")
      IF (present_mat) THEN
         ! Give back the vectors generating the rototranslating Frame
         ALLOCATE (mat(natoms*3, dof))
         iseq = 0
         DO i = 1, 3
            mat(:, i) = Tr(:, i)
            IF (lrot(i) == 1) THEN
               iseq = iseq + 1
               mat(:, 3 + iseq) = Rot(:, i)
            END IF
         END DO
      END IF
      DEALLOCATE (Tr)
      DEALLOCATE (Rot)
      CALL timestop(handle)

   END SUBROUTINE rot_ana

! **************************************************************************************************
!> \brief   Prints the information controlled by the TRAJECTORY section
!> \param force_env ...
!> \param root_section ...
!> \param it ...
!> \param time ...
!> \param dtime ...
!> \param etot ...
!> \param pk_name ...
!> \param pos ...
!> \param act ...
!> \param middle_name ...
!> \param particles ...
!> \param extended_xmol_title ...
!> \date    02.2008
!> \author  Teodoro Laino [tlaino] - University of Zurich
!> \version 1.0
! **************************************************************************************************
   SUBROUTINE write_trajectory(force_env, root_section, it, time, dtime, etot, pk_name, &
                               pos, act, middle_name, particles, extended_xmol_title)
      TYPE(force_env_type), POINTER                      :: force_env
      TYPE(section_vals_type), POINTER                   :: root_section
      INTEGER, INTENT(IN)                                :: it
      REAL(KIND=dp), INTENT(IN)                          :: time, dtime, etot
      CHARACTER(LEN=*), OPTIONAL                         :: pk_name
      CHARACTER(LEN=default_string_length), OPTIONAL     :: pos, act
      CHARACTER(LEN=*), OPTIONAL                         :: middle_name
      TYPE(particle_list_type), OPTIONAL, POINTER        :: particles
      LOGICAL, INTENT(IN), OPTIONAL                      :: extended_xmol_title

      CHARACTER(LEN=*), PARAMETER                        :: routineN = 'write_trajectory'

      CHARACTER(LEN=4)                                   :: id_dcd
      CHARACTER(LEN=default_string_length)               :: id_label, id_wpc, my_act, my_ext, &
                                                            my_form, my_middle, my_pk_name, &
                                                            my_pos, remark1, remark2, section_ref, &
                                                            title, unit_str
      INTEGER                                            :: handle, i, ii, iskip, nat, outformat, &
                                                            traj_unit
      INTEGER, POINTER                                   :: force_mixing_indices(:), &
                                                            force_mixing_labels(:)
      LOGICAL                                            :: charge_beta, charge_extended, &
                                                            charge_occup, explicit, &
                                                            my_extended_xmol_title, new_file, &
                                                            print_kind
      REAL(dp), ALLOCATABLE                              :: fml_array(:)
      REAL(KIND=dp)                                      :: unit_conv
      TYPE(cell_type), POINTER                           :: cell
      TYPE(cp_logger_type), POINTER                      :: logger
      TYPE(cp_subsys_type), POINTER                      :: subsys
      TYPE(particle_list_type), POINTER                  :: my_particles
      TYPE(particle_type), DIMENSION(:), POINTER         :: particle_set
      TYPE(section_vals_type), POINTER                   :: force_env_section, &
                                                            force_mixing_restart_section

      CALL timeset(routineN, handle)

      NULLIFY (logger, cell, subsys, my_particles, particle_set)
      logger => cp_get_default_logger()
      id_label = logger%iter_info%level_name(logger%iter_info%n_rlevel)
      my_pos = "APPEND"
      my_act = "WRITE"
      my_middle = "pos"
      my_pk_name = "TRAJECTORY"
      IF (PRESENT(middle_name)) my_middle = middle_name
      IF (PRESENT(pos)) my_pos = pos
      IF (PRESENT(act)) my_act = act
      IF (PRESENT(pk_name)) my_pk_name = pk_name

      SELECT CASE (TRIM(my_pk_name))
      CASE ("TRAJECTORY", "SHELL_TRAJECTORY", "CORE_TRAJECTORY")
         id_dcd = "CORD"
         id_wpc = "POS"
      CASE ("VELOCITIES", "SHELL_VELOCITIES", "CORE_VELOCITIES")
         id_dcd = "VEL "
         id_wpc = "VEL"
      CASE ("FORCES", "SHELL_FORCES", "CORE_FORCES")
         id_dcd = "FRC "
         id_wpc = "FORCE"
      CASE ("FORCE_MIXING_LABELS")
         id_dcd = "FML "
         id_wpc = "FORCE_MIXING_LABELS"
      CASE DEFAULT
         CPABORT("")
      END SELECT

      charge_occup = .FALSE.
      charge_beta = .FALSE.
      charge_extended = .FALSE.
      print_kind = .FALSE.

      CALL force_env_get(force_env, cell=cell, subsys=subsys)
      IF (PRESENT(particles)) THEN
         CPASSERT(ASSOCIATED(particles))
         my_particles => particles
      ELSE
         CALL cp_subsys_get(subsys=subsys, particles=my_particles)
      END IF
      particle_set => my_particles%els
      nat = my_particles%n_els

      ! Gather units of measure for output (if available)
      IF (TRIM(my_pk_name) /= "FORCE_MIXING_LABELS") THEN
         CALL section_vals_val_get(root_section, "MOTION%PRINT%"//TRIM(my_pk_name)//"%UNIT", &
                                   c_val=unit_str)
         unit_conv = cp_unit_from_cp2k(1.0_dp, TRIM(unit_str))
      END IF

      ! Get the output format
      CALL get_output_format(root_section, "MOTION%PRINT%"//TRIM(my_pk_name), my_form, my_ext)
      traj_unit = cp_print_key_unit_nr(logger, root_section, "MOTION%PRINT%"//TRIM(my_pk_name), &
                                       extension=my_ext, file_position=my_pos, file_action=my_act, &
                                       file_form=my_form, middle_name=TRIM(my_middle), is_new_file=new_file)
      IF (traj_unit > 0) THEN
         CALL section_vals_val_get(root_section, "MOTION%PRINT%"//TRIM(my_pk_name)//"%FORMAT", &
                                   i_val=outformat)
         title = ""
         SELECT CASE (outformat)
         CASE (dump_dcd, dump_dcd_aligned_cell)
            IF (new_file) THEN
               !Lets write the header for the coordinate dcd
               section_ref = "MOTION%PRINT%"//TRIM(my_pk_name)//"%EACH%"//TRIM(id_label)
               iskip = section_get_ival(root_section, TRIM(section_ref))
               WRITE (UNIT=traj_unit) id_dcd, 0, it, iskip, 0, 0, 0, 0, 0, 0, REAL(dtime, KIND=sp), &
                  1, 0, 0, 0, 0, 0, 0, 0, 0, 24
               remark1 = "REMARK "//id_dcd//" DCD file created by "//TRIM(cp2k_version)// &
                         " (revision "//TRIM(compile_revision)//")"
               remark2 = "REMARK "//TRIM(r_user_name)//"@"//TRIM(r_host_name)
               WRITE (UNIT=traj_unit) 2, remark1, remark2
               WRITE (UNIT=traj_unit) nat
               CALL m_flush(traj_unit)
            END IF
         CASE (dump_xmol)
            my_extended_xmol_title = .FALSE.
            CALL section_vals_val_get(root_section, "MOTION%PRINT%TRAJECTORY%PRINT_ATOM_KIND", &
                                      l_val=print_kind)
            IF (PRESENT(extended_xmol_title)) my_extended_xmol_title = extended_xmol_title
            ! This information can be digested by Molden
            IF (my_extended_xmol_title) THEN
               WRITE (UNIT=title, FMT="(A,I8,A,F12.3,A,F20.10)") &
                  " i = ", it, ", time = ", time, ", E = ", etot
            ELSE
               WRITE (UNIT=title, FMT="(A,I8,A,F20.10)") " i = ", it, ", E = ", etot
            END IF
         CASE (dump_atomic)
            ! Do nothing
         CASE (dump_pdb)
            IF (id_wpc == "POS") THEN
               CALL section_vals_val_get(root_section, "MOTION%PRINT%TRAJECTORY%CHARGE_OCCUP", &
                                         l_val=charge_occup)
               CALL section_vals_val_get(root_section, "MOTION%PRINT%TRAJECTORY%CHARGE_BETA", &
                                         l_val=charge_beta)
               CALL section_vals_val_get(root_section, "MOTION%PRINT%TRAJECTORY%CHARGE_EXTENDED", &
                                         l_val=charge_extended)
               i = COUNT((/charge_occup, charge_beta, charge_extended/))
               IF (i > 1) &
                  CPABORT("Either only CHARGE_OCCUP, CHARGE_BETA, or CHARGE_EXTENDED can be selected, ")
            END IF
            IF (new_file) THEN
               ! COLUMNS        DATA TYPE       FIELD          DEFINITION
               !  1 -  6        Record name     "TITLE "
               !  9 - 10        Continuation    continuation   Allows concatenation
               ! 11 - 70        String          title          Title of the experiment
               WRITE (UNIT=traj_unit, FMT="(A6,T11,A)") &
                  "TITLE ", "PDB file created by "//TRIM(cp2k_version)//" (revision "//TRIM(compile_revision)//")", &
                  "AUTHOR", TRIM(r_user_name)//"@"//TRIM(r_host_name)//" "//r_datx(1:19)
            END IF
            my_extended_xmol_title = .FALSE.
            IF (PRESENT(extended_xmol_title)) my_extended_xmol_title = extended_xmol_title
            IF (my_extended_xmol_title) THEN
               WRITE (UNIT=title, FMT="(A,I0,A,F0.3,A,F0.10)") &
                  "Step ", it, ", time = ", time, ", E = ", etot
            ELSE
               WRITE (UNIT=title, FMT="(A,I0,A,F0.10)") &
                  "Step ", it, ", E = ", etot
            END IF
         CASE DEFAULT
            CPABORT("")
         END SELECT
         IF (TRIM(my_pk_name) == "FORCE_MIXING_LABELS") THEN
            ALLOCATE (fml_array(3*SIZE(particle_set)))
            fml_array = 0.0_dp
            CALL force_env_get(force_env, force_env_section=force_env_section)
            force_mixing_restart_section => section_vals_get_subs_vals(force_env_section, &
                                                                       "QMMM%FORCE_MIXING%RESTART_INFO", &
                                                                       can_return_null=.TRUE.)
            IF (ASSOCIATED(force_mixing_restart_section)) THEN
               CALL section_vals_get(force_mixing_restart_section, explicit=explicit)
               IF (explicit) THEN
                  CALL section_vals_val_get(force_mixing_restart_section, "INDICES", i_vals=force_mixing_indices)
                  CALL section_vals_val_get(force_mixing_restart_section, "LABELS", i_vals=force_mixing_labels)
                  DO i = 1, SIZE(force_mixing_indices)
                     ii = force_mixing_indices(i)
                     CPASSERT(ii <= SIZE(particle_set))
                     fml_array((ii - 1)*3 + 1:(ii - 1)*3 + 3) = force_mixing_labels(i)
                  END DO
               END IF
            END IF
            CALL write_particle_coordinates(particle_set, traj_unit, outformat, TRIM(id_wpc), TRIM(title), cell, &
                                            array=fml_array, print_kind=print_kind)
            DEALLOCATE (fml_array)
         ELSE
            CALL write_particle_coordinates(particle_set, traj_unit, outformat, TRIM(id_wpc), TRIM(title), cell, &
                                            unit_conv=unit_conv, print_kind=print_kind, &
                                            charge_occup=charge_occup, &
                                            charge_beta=charge_beta, &
                                            charge_extended=charge_extended)
         END IF
      END IF

      CALL cp_print_key_finished_output(traj_unit, logger, root_section, "MOTION%PRINT%"//TRIM(my_pk_name))

      CALL timestop(handle)

   END SUBROUTINE write_trajectory

! **************************************************************************************************
!> \brief Info on the unit to be opened to dump MD informations
!> \param section ...
!> \param path ...
!> \param my_form ...
!> \param my_ext ...
!> \author Teodoro Laino - University of Zurich - 07.2007
! **************************************************************************************************
   SUBROUTINE get_output_format(section, path, my_form, my_ext)

      TYPE(section_vals_type), POINTER                   :: section
      CHARACTER(LEN=*), INTENT(IN), OPTIONAL             :: path
      CHARACTER(LEN=*), INTENT(OUT)                      :: my_form, my_ext

      INTEGER                                            :: output_format

      IF (PRESENT(path)) THEN
         CALL section_vals_val_get(section, TRIM(path)//"%FORMAT", i_val=output_format)
      ELSE
         CALL section_vals_val_get(section, "FORMAT", i_val=output_format)
      END IF

      SELECT CASE (output_format)
      CASE (dump_dcd, dump_dcd_aligned_cell)
         my_form = "UNFORMATTED"
         my_ext = ".dcd"
      CASE (dump_pdb)
         my_form = "FORMATTED"
         my_ext = ".pdb"
      CASE DEFAULT
         my_form = "FORMATTED"
         my_ext = ".xyz"
      END SELECT

   END SUBROUTINE get_output_format

! **************************************************************************************************
!> \brief   Prints the Stress Tensor
!> \param virial ...
!> \param cell ...
!> \param motion_section ...
!> \param itimes ...
!> \param time ...
!> \param pos ...
!> \param act ...
!> \date    02.2008
!> \author  Teodoro Laino [tlaino] - University of Zurich
!> \version 1.0
! **************************************************************************************************
   SUBROUTINE write_stress_tensor_to_file(virial, cell, motion_section, itimes, time, pos, act)

      TYPE(virial_type), POINTER                         :: virial
      TYPE(cell_type), POINTER                           :: cell
      TYPE(section_vals_type), POINTER                   :: motion_section
      INTEGER, INTENT(IN)                                :: itimes
      REAL(KIND=dp), INTENT(IN)                          :: time
      CHARACTER(LEN=default_string_length), INTENT(IN), &
         OPTIONAL                                        :: pos, act

      CHARACTER(LEN=default_string_length)               :: my_act, my_pos
      INTEGER                                            :: output_unit
      LOGICAL                                            :: new_file
      REAL(KIND=dp), DIMENSION(3, 3)                     :: pv_total_bar
      TYPE(cp_logger_type), POINTER                      :: logger

      NULLIFY (logger)
      logger => cp_get_default_logger()

      IF (virial%pv_availability) THEN
         my_pos = "APPEND"
         my_act = "WRITE"
         IF (PRESENT(pos)) my_pos = pos
         IF (PRESENT(act)) my_act = act
         output_unit = cp_print_key_unit_nr(logger, motion_section, "PRINT%STRESS", &
                                            extension=".stress", file_position=my_pos, &
                                            file_action=my_act, file_form="FORMATTED", &
                                            is_new_file=new_file)
      ELSE
         output_unit = 0
      END IF

      IF (output_unit > 0) THEN
         IF (new_file) THEN
            WRITE (UNIT=output_unit, FMT='(A,9(12X,A2," [bar]"),6X,A)') &
               "#   Step   Time [fs]", "xx", "xy", "xz", "yx", "yy", "yz", "zx", "zy", "zz"
         END IF
         pv_total_bar(1, 1) = cp_unit_from_cp2k(virial%pv_total(1, 1)/cell%deth, "bar")
         pv_total_bar(1, 2) = cp_unit_from_cp2k(virial%pv_total(1, 2)/cell%deth, "bar")
         pv_total_bar(1, 3) = cp_unit_from_cp2k(virial%pv_total(1, 3)/cell%deth, "bar")
         pv_total_bar(2, 1) = cp_unit_from_cp2k(virial%pv_total(2, 1)/cell%deth, "bar")
         pv_total_bar(2, 2) = cp_unit_from_cp2k(virial%pv_total(2, 2)/cell%deth, "bar")
         pv_total_bar(2, 3) = cp_unit_from_cp2k(virial%pv_total(2, 3)/cell%deth, "bar")
         pv_total_bar(3, 1) = cp_unit_from_cp2k(virial%pv_total(3, 1)/cell%deth, "bar")
         pv_total_bar(3, 2) = cp_unit_from_cp2k(virial%pv_total(3, 2)/cell%deth, "bar")
         pv_total_bar(3, 3) = cp_unit_from_cp2k(virial%pv_total(3, 3)/cell%deth, "bar")
         WRITE (UNIT=output_unit, FMT='(I8,F12.3,9(1X,F19.10))') itimes, time, &
            pv_total_bar(1, 1), pv_total_bar(1, 2), pv_total_bar(1, 3), &
            pv_total_bar(2, 1), pv_total_bar(2, 2), pv_total_bar(2, 3), &
            pv_total_bar(3, 1), pv_total_bar(3, 2), pv_total_bar(3, 3)
         CALL m_flush(output_unit)
      END IF

      IF (virial%pv_availability) THEN
         CALL cp_print_key_finished_output(output_unit, logger, motion_section, &
                                           "PRINT%STRESS")
      END IF

   END SUBROUTINE write_stress_tensor_to_file

! **************************************************************************************************
!> \brief   Prints the Simulation Cell
!> \param cell ...
!> \param motion_section ...
!> \param itimes ...
!> \param time ...
!> \param pos ...
!> \param act ...
!> \date    02.2008
!> \author  Teodoro Laino [tlaino] - University of Zurich
!> \version 1.0
! **************************************************************************************************
   SUBROUTINE write_simulation_cell(cell, motion_section, itimes, time, pos, act)

      TYPE(cell_type), POINTER                           :: cell
      TYPE(section_vals_type), POINTER                   :: motion_section
      INTEGER, INTENT(IN)                                :: itimes
      REAL(KIND=dp), INTENT(IN)                          :: time
      CHARACTER(LEN=default_string_length), INTENT(IN), &
         OPTIONAL                                        :: pos, act

      CHARACTER(LEN=default_string_length)               :: my_act, my_pos
      INTEGER                                            :: output_unit
      LOGICAL                                            :: new_file
      TYPE(cp_logger_type), POINTER                      :: logger

      NULLIFY (logger)
      logger => cp_get_default_logger()

      my_pos = "APPEND"
      my_act = "WRITE"
      IF (PRESENT(pos)) my_pos = pos
      IF (PRESENT(act)) my_act = act

      output_unit = cp_print_key_unit_nr(logger, motion_section, "PRINT%CELL", &
                                         extension=".cell", file_position=my_pos, &
                                         file_action=my_act, file_form="FORMATTED", &
                                         is_new_file=new_file)

      IF (output_unit > 0) THEN
         IF (new_file) THEN
            WRITE (UNIT=output_unit, FMT='(A,9(7X,A2," [Angstrom]"),6X,A)') &
               "#   Step   Time [fs]", "Ax", "Ay", "Az", "Bx", "By", "Bz", "Cx", "Cy", "Cz", &
               "Volume [Angstrom^3]"
         END IF
         WRITE (UNIT=output_unit, FMT="(I8,F12.3,9(1X,F19.10),1X,F24.10)") itimes, time, &
            cell%hmat(1, 1)*angstrom, cell%hmat(2, 1)*angstrom, cell%hmat(3, 1)*angstrom, &
            cell%hmat(1, 2)*angstrom, cell%hmat(2, 2)*angstrom, cell%hmat(3, 2)*angstrom, &
            cell%hmat(1, 3)*angstrom, cell%hmat(2, 3)*angstrom, cell%hmat(3, 3)*angstrom, &
            cell%deth*angstrom*angstrom*angstrom
         CALL m_flush(output_unit)
      END IF

      CALL cp_print_key_finished_output(output_unit, logger, motion_section, &
                                        "PRINT%CELL")

   END SUBROUTINE write_simulation_cell

END MODULE motion_utils
