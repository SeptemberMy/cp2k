!--------------------------------------------------------------------------------------------------!
!   CP2K: A general program to perform molecular dynamics simulations                              !
!   Copyright 2000-2025 CP2K developers group <https://cp2k.org>                                   !
!                                                                                                  !
!   SPDX-License-Identifier: GPL-2.0-or-later                                                      !
!--------------------------------------------------------------------------------------------------!

! **************************************************************************************************
MODULE farming_methods
   USE cp_files,                        ONLY: get_unit_number
   USE cp_log_handling,                 ONLY: cp_get_default_logger,&
                                              cp_logger_type
   USE cp_output_handling,              ONLY: cp_print_key_finished_output,&
                                              cp_print_key_generate_filename,&
                                              cp_print_key_unit_nr
   USE farming_types,                   ONLY: farming_env_type,&
                                              init_job_type,&
                                              job_finished,&
                                              job_pending,&
                                              job_running
   USE input_section_types,             ONLY: section_vals_get,&
                                              section_vals_get_subs_vals,&
                                              section_vals_type,&
                                              section_vals_val_get
   USE message_passing,                 ONLY: mp_para_env_type
#include "./base/base_uses.f90"

   IMPLICIT NONE
   PRIVATE
   PUBLIC  :: farming_parse_input, get_next_job

   ! must be negative in order to avoid confusion with job numbers
   INTEGER, PARAMETER, PUBLIC    :: do_nothing = -1, &
                                    do_wait = -2, &
                                    do_deadlock = -3

   CHARACTER(len=*), PARAMETER, PRIVATE :: moduleN = 'farming_methods'

CONTAINS

! **************************************************************************************************
!> \brief ...
!> \param farming_env ...
!> \param start ...
!> \param END ...
!> \param current ...
!> \param todo ...
! **************************************************************************************************
   SUBROUTINE get_next_job(farming_env, start, END, current, todo)
      TYPE(farming_env_type), POINTER                    :: farming_env
      INTEGER, INTENT(IN)                                :: start, END
      INTEGER, INTENT(INOUT)                             :: current
      INTEGER, INTENT(OUT)                               :: todo

      INTEGER                                            :: icheck, idep, itry, ndep
      LOGICAL                                            :: dep_ok

      IF (farming_env%cycle) THEN
         IF (current < start) THEN
            current = start
         ELSE
            current = current + 1
         END IF
         IF (current > END) THEN
            todo = do_nothing
         ELSE
            todo = MODULO(current - 1, farming_env%njobs) + 1
         END IF
      ELSE
         ! find a pending job
         itry = start
         todo = do_nothing
         DO itry = start, END
            IF (farming_env%job(itry)%status == job_pending) THEN

               ! see if all dependencies are OK
               ndep = SIZE(farming_env%job(itry)%dependencies)
               dep_ok = .TRUE.
               dep: DO idep = 1, ndep
                  DO icheck = start, END
                     IF (farming_env%job(icheck)%status .NE. job_finished) THEN
                        IF (farming_env%job(icheck)%id == farming_env%job(itry)%dependencies(idep)) THEN
                           dep_ok = .FALSE.
                           EXIT dep
                        END IF
                     END IF
                  END DO
               END DO dep

               ! if there are pending jobs, the minion can not be told to stop
               ! at least wait if there are unresolved dependencies
               IF (dep_OK) THEN
                  todo = itry
                  EXIT
               ELSE
                  todo = do_wait
               END IF
            END IF
         END DO
         ! If we have to wait, but there are no running jobs we are deadlocked
         ! which we signal
         IF (todo == do_wait) THEN
            dep_OK = .FALSE.
            DO itry = start, END
               IF (farming_env%job(itry)%status .EQ. job_running) dep_OK = .TRUE.
            END DO
            IF (.NOT. dep_OK) todo = do_deadlock
         END IF
      END IF
   END SUBROUTINE get_next_job

! **************************************************************************************************
!> \brief ...
!> \param farming_env ...
!> \param root_section ...
!> \param para_env ...
! **************************************************************************************************
   SUBROUTINE farming_parse_input(farming_env, root_section, para_env)
      TYPE(farming_env_type), POINTER                    :: farming_env
      TYPE(section_vals_type), POINTER                   :: root_section
      TYPE(mp_para_env_type), POINTER                    :: para_env

      CHARACTER(LEN=3)                                   :: text
      INTEGER                                            :: i, iunit, n_rep_val, num_minions, &
                                                            output_unit, stat
      INTEGER, DIMENSION(:), POINTER                     :: dependencies, i_vals
      LOGICAL                                            :: explicit, has_dep
      TYPE(cp_logger_type), POINTER                      :: logger
      TYPE(section_vals_type), POINTER                   :: farming_section, jobs_section, print_key

      NULLIFY (farming_section, jobs_section, print_key, logger, dependencies, i_vals)
      logger => cp_get_default_logger()
      farming_env%group_size_wish_set = .FALSE.
      farming_env%ngroup_wish_set = .FALSE.
      farming_section => section_vals_get_subs_vals(root_section, "FARMING")

      IF (ASSOCIATED(farming_env%group_partition)) THEN
         DEALLOCATE (farming_env%group_partition)
      END IF

      ! The following input order is used
      ! 1) GROUP_PARTITION
      ! 2) NGROUP
      ! 3) GROUP_SIZE (default 8)
      CALL section_vals_val_get(farming_section, "GROUP_PARTITION", &
                                n_rep_val=n_rep_val)
      IF (n_rep_val > 0) THEN
         CALL section_vals_val_get(farming_section, "GROUP_PARTITION", &
                                   i_vals=i_vals)
         ALLOCATE (farming_env%group_partition(0:SIZE(i_vals) - 1))
         farming_env%group_partition(:) = i_vals
         farming_env%ngroup_wish_set = .TRUE.
         farming_env%ngroup_wish = SIZE(i_vals)
      ELSE
         CALL section_vals_val_get(farming_section, "NGROUP", &
                                   n_rep_val=n_rep_val)
         IF (n_rep_val > 0) THEN
            CALL section_vals_val_get(farming_section, "NGROUP", &
                                      i_val=farming_env%ngroup_wish)
            farming_env%ngroup_wish_set = .TRUE.
         ELSE
            CALL section_vals_val_get(farming_section, "GROUP_SIZE", &
                                      i_val=farming_env%group_size_wish)
            farming_env%group_size_wish_set = .TRUE.
         END IF
      END IF
      CALL section_vals_val_get(farming_section, "STRIDE", &
                                i_val=farming_env%stride)

      CALL section_vals_val_get(farming_section, "RESTART_FILE_NAME", &
                                explicit=explicit)
      IF (explicit) THEN
         CALL section_vals_val_get(farming_section, "RESTART_FILE_NAME", &
                                   c_val=farming_env%restart_file_name)
      ELSE
         print_key => section_vals_get_subs_vals(farming_section, "RESTART")
         farming_env%restart_file_name = cp_print_key_generate_filename(logger, print_key, extension=".restart", &
                                                                        my_local=.FALSE.)
      END IF

      CALL section_vals_val_get(farming_section, "DO_RESTART", &
                                l_val=farming_env%restart)
      CALL section_vals_val_get(farming_section, "MAX_JOBS_PER_GROUP", &
                                i_val=farming_env%max_steps)
      CALL section_vals_val_get(farming_section, "CYCLE", &
                                l_val=farming_env%cycle)
      CALL section_vals_val_get(farming_section, "WAIT_TIME", &
                                r_val=farming_env%wait_time)

      CALL section_vals_val_get(farming_section, "CAPTAIN_MINION", &
                                l_val=farming_env%captain_minion)

      jobs_section => section_vals_get_subs_vals(farming_section, "JOB")
      CALL section_vals_get(jobs_section, n_repetition=farming_env%njobs)

      ALLOCATE (farming_env%Job(farming_env%njobs))
      CALL init_job_type(farming_env%job)

      has_dep = .FALSE.
      DO i = 1, farming_env%njobs
         CALL section_vals_val_get(jobs_section, i_rep_section=i, &
                                   keyword_name="DIRECTORY", c_val=farming_env%Job(i)%cwd)
         CALL section_vals_val_get(jobs_section, i_rep_section=i, &
                                   keyword_name="INPUT_FILE_NAME", c_val=farming_env%Job(i)%input)
         CALL section_vals_val_get(jobs_section, i_rep_section=i, &
                                   keyword_name="OUTPUT_FILE_NAME", c_val=farming_env%Job(i)%output)

         ! if job id is not specified the job id is the index
         CALL section_vals_val_get(jobs_section, i_rep_section=i, &
                                   keyword_name="JOB_ID", n_rep_val=n_rep_val)
         IF (n_rep_val == 0) THEN
            farming_env%Job(i)%id = i
         ELSE
            CALL section_vals_val_get(jobs_section, i_rep_section=i, &
                                      keyword_name="JOB_ID", i_val=farming_env%Job(i)%id)
         END IF

         ! get dependencies
         CALL section_vals_val_get(jobs_section, i_rep_section=i, &
                                   keyword_name="DEPENDENCIES", n_rep_val=n_rep_val)
         IF (n_rep_val == 0) THEN
            ALLOCATE (farming_env%Job(i)%dependencies(0))
         ELSE
            CALL section_vals_val_get(jobs_section, i_rep_section=i, &
                                      keyword_name="DEPENDENCIES", i_vals=dependencies)
            ALLOCATE (farming_env%Job(i)%dependencies(SIZE(dependencies, 1)))
            farming_env%Job(i)%dependencies = dependencies
            IF (SIZE(dependencies, 1) .NE. 0) has_dep = .TRUE.
         END IF
      END DO

      IF (has_dep) THEN
         CPASSERT(farming_env%captain_minion)
         CPASSERT(.NOT. farming_env%cycle)
      END IF

      output_unit = cp_print_key_unit_nr(logger, farming_section, "PROGRAM_RUN_INFO", &
                                         extension=".log")

      ! Captain/Minion not supported
      IF (para_env%num_pe == 1) THEN
         farming_env%captain_minion = .FALSE.
         WRITE (output_unit, FMT="(T2,A)") "FARMING| Captain-Minion setup not supported for serial runs"
      END IF
      IF (farming_env%captain_minion) THEN
         num_minions = para_env%num_pe - 1
      ELSE
         num_minions = para_env%num_pe
      END IF

      IF (output_unit > 0) THEN
         WRITE (output_unit, FMT="(T2,A,T71,I10)") "FARMING| Number of jobs found", farming_env%njobs
         IF (farming_env%ngroup_wish_set) THEN
            WRITE (output_unit, FMT="(T2,A,T71,I10)") "FARMING| Ngroup wish:", farming_env%ngroup_wish
            IF (ASSOCIATED(farming_env%group_partition)) THEN
               WRITE (output_unit, FMT="(T2,A)", ADVANCE="NO") "FARMING| User partition:"
               DO i = 0, SIZE(farming_env%group_partition) - 1
                  IF (MODULO(i, 4) == 0) WRITE (output_unit, *)
                  WRITE (output_unit, FMT='(I4)', ADVANCE="NO") farming_env%group_partition(i)
               END DO
               WRITE (output_unit, *)
               IF (SUM(farming_env%group_partition) .NE. num_minions) THEN
                  WRITE (output_unit, FMT="(T2,A,T61,I10,T71,I10)") &
                     "FARMING| WARNING : group partition CPUs not equal to the available number (ignoring Captain) ", &
                     num_minions, SUM(farming_env%group_partition)
                  WRITE (output_unit, FMT="(T2,A)") "FARMING|          partition data ignored" ! any better idea ??
                  DEALLOCATE (farming_env%group_partition)
               END IF
            END IF
         END IF
         IF (farming_env%group_size_wish_set) THEN
            WRITE (output_unit, FMT="(T2,A,T71,I10)") "FARMING| Group size wish:", &
               farming_env%group_size_wish
         END IF
         WRITE (output_unit, FMT="(T2,A,T71,I10)") "FARMING| Max steps      :", farming_env%max_steps
         IF (farming_env%cycle) THEN
            text = "YES"
         ELSE
            text = " NO"
         END IF
         WRITE (output_unit, FMT="(T2,A,T78,A3)") "FARMING| Cyclic jobs execution:", text
         IF (farming_env%restart) THEN
            text = "YES"
         ELSE
            text = " NO"
         END IF
         WRITE (output_unit, FMT="(T2,A,T78,A3)") "FARMING| Restarting farm:", text
         farming_env%restart_n = 1
         IF (farming_env%restart) THEN
            iunit = get_unit_number()
            OPEN (UNIT=iunit, FILE=farming_env%restart_file_name, IOSTAT=stat)
            IF (stat == 0) THEN
               READ (UNIT=iunit, FMT=*, IOSTAT=stat) farming_env%restart_n
               IF (stat /= 0) THEN
                  WRITE (output_unit, "(T2,A)") &
                     "FARMING| ---- WARNING ---- failed to read from ("//TRIM(farming_env%restart_file_name)//") starting at 1"
               ELSE
                  WRITE (output_unit, "(T2,A)") &
                     "FARMING| restarting from ("//TRIM(farming_env%restart_file_name)//")"
                  WRITE (output_unit, "(T2,A,T71,I10)") &
                     "FARMING| restarting at ", farming_env%restart_n
               END IF
            ELSE
               WRITE (output_unit, "(T2,A)") &
                  "FARMING| ---- WARNING ---- failed to open ("//TRIM(farming_env%restart_file_name)//"), starting at 1"
            END IF
            CLOSE (iunit, IOSTAT=stat)
         END IF

         CALL cp_print_key_finished_output(output_unit, logger, farming_section, &
                                           "PROGRAM_RUN_INFO")
      END IF
      CALL para_env%bcast(farming_env%restart_n)

   END SUBROUTINE

END MODULE farming_methods
