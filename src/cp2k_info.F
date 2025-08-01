!--------------------------------------------------------------------------------------------------!
!   CP2K: A general program to perform molecular dynamics simulations                              !
!   Copyright 2000-2025 CP2K developers group <https://cp2k.org>                                   !
!                                                                                                  !
!   SPDX-License-Identifier: GPL-2.0-or-later                                                      !
!--------------------------------------------------------------------------------------------------!

! **************************************************************************************************
!> \brief some minimal info about CP2K, including its version and license
!> \par History
!>      - created (2007-09, Joost VandeVondele)
!>      - moved into this module information related to runtime:pid, user_name,
!>        host_name, cwd, datx  (2009-06, Teodoro Laino)
!> \author Joost VandeVondele
! **************************************************************************************************
MODULE cp2k_info

   USE iso_fortran_env,                 ONLY: compiler_options
   USE kinds,                           ONLY: default_path_length,&
                                              default_string_length
   USE machine,                         ONLY: m_datum,&
                                              m_getcwd,&
                                              m_getlog,&
                                              m_getpid,&
                                              m_hostnm
   USE string_utilities,                ONLY: integer_to_string

   IMPLICIT NONE
   PRIVATE

   PUBLIC :: cp2k_version, cp2k_year, cp2k_home, cp2k_flags
   PUBLIC :: compile_arch, compile_date, compile_host, compile_revision
   PUBLIC :: print_cp2k_license, get_runtime_info, write_restart_header

#if defined(__COMPILE_REVISION)
   CHARACTER(LEN=*), PARAMETER :: compile_revision = __COMPILE_REVISION
#else
   CHARACTER(LEN=*), PARAMETER :: compile_revision = "unknown"
#endif

   !!! Keep version in sync with CMakeLists.txt !!!
   CHARACTER(LEN=*), PARAMETER :: cp2k_version = "CP2K version 2025.2 (Development Version)"
   CHARACTER(LEN=*), PARAMETER :: cp2k_year = "2025"
   CHARACTER(LEN=*), PARAMETER :: cp2k_home = "https://www.cp2k.org/"

   ! compile time information
#if defined(__COMPILE_ARCH)
   CHARACTER(LEN=*), PARAMETER :: compile_arch = __COMPILE_ARCH
#else
   CHARACTER(LEN=*), PARAMETER :: compile_arch = "unknown: -D__COMPILE_ARCH=?"
#endif

#if defined(__COMPILE_DATE)
   CHARACTER(LEN=*), PARAMETER :: compile_date = __COMPILE_DATE
#else
   CHARACTER(LEN=*), PARAMETER :: compile_date = "unknown: -D__COMPILE_DATE=?"
#endif

#if defined(__COMPILE_HOST)
   CHARACTER(LEN=*), PARAMETER :: compile_host = __COMPILE_HOST
#else
   CHARACTER(LEN=*), PARAMETER :: compile_host = "unknown: -D__COMPILE_HOST=?"
#endif

   ! Local runtime informations
   CHARACTER(LEN=26), PUBLIC                        :: r_datx
   CHARACTER(LEN=default_path_length), PUBLIC       :: r_cwd
   CHARACTER(LEN=default_string_length), PUBLIC     :: r_host_name, r_user_name
   INTEGER, PUBLIC                                  :: r_pid

   CHARACTER(len=*), PARAMETER, PRIVATE :: moduleN = 'cp2k_info'
CONTAINS

! **************************************************************************************************
!> \brief list all compile time options that influence the capabilities of cp2k.
!>        All new flags should be added here (and be unique grep-able)
!> \return ...
! **************************************************************************************************
   FUNCTION cp2k_flags() RESULT(flags)
      CHARACTER(len=10*default_string_length)            :: flags

      CHARACTER(len=default_string_length)               :: tmp_str

      flags = "cp2kflags:"

      ! Ensure that tmp_str is used to silence compiler warnings
      tmp_str = ""
      flags = TRIM(flags)//TRIM(tmp_str)

      IF (INDEX(COMPILER_OPTIONS(), "-fsanitize=leak") > 0) THEN
         flags = TRIM(flags)//" lsan"
      END IF

!$    flags = TRIM(flags)//" omp"
#if defined(__LIBINT)
      flags = TRIM(flags)//" libint"
#endif
#if defined(__FFTW3)
      flags = TRIM(flags)//" fftw3"
#endif
#if defined(__LIBXC)
      flags = TRIM(flags)//" libxc"
#endif
#if defined(__LIBGRPP)
      flags = TRIM(flags)//" libgrpp"
#endif
#if defined(__PEXSI)
      flags = TRIM(flags)//" pexsi"
#endif
#if defined(__ELPA)
      flags = TRIM(flags)//" elpa"
#endif
#if defined(__ELPA_NVIDIA_GPU)
      flags = TRIM(flags)//" elpa_nvidia_gpu"
#endif
#if defined(__ELPA_AMD_GPU)
      flags = TRIM(flags)//" elpa_amd_gpu"
#endif
#if defined(__ELPA_INTEL_GPU)
      flags = TRIM(flags)//" elpa_intel_gpu"
#endif
#if defined(__parallel)
      flags = TRIM(flags)//" parallel scalapack"
#endif
#if defined(__MPI_F08)
      flags = TRIM(flags)//" mpi_f08"
#endif
#if defined(__COSMA)
      flags = TRIM(flags)//" cosma"
#endif

#if defined(__QUIP)
      flags = TRIM(flags)//" quip"
#endif

#if defined(__HAS_PATCHED_CUFFT_70)
      flags = TRIM(flags)//" patched_cufft_70"
#endif

#if defined(__ACE)
      flags = TRIM(flags)//" ace"
#endif

#if defined(__DEEPMD)
      flags = TRIM(flags)//" deepmd"
#endif

#if defined(__PW_FPGA)
      flags = TRIM(flags)//" pw_fpga"
#endif

#if defined(__PW_FPGA_SP)
      flags = TRIM(flags)//" pw_fpga_sp"
#endif

#if defined(__LIBXSMM)
      flags = TRIM(flags)//" xsmm"
#endif

#if defined(__CRAY_PM_ACCEL_ENERGY)
      flags = TRIM(flags)//" cray_pm_accel_energy"
#endif
#if defined(__CRAY_PM_ENERGY)
      flags = TRIM(flags)//" cray_pm_energy"
#endif
#if defined(__CRAY_PM_FAKE_ENERGY)
      flags = TRIM(flags)//" cray_pm_fake_energy"
#endif
#if defined(__DBCSR_ACC)
      flags = TRIM(flags)//" dbcsr_acc"
#endif
#if defined(__MAX_CONTR)
      CALL integer_to_string(__MAX_CONTR, tmp_str)
      flags = TRIM(flags)//" max_contr="//TRIM(tmp_str)
#endif
#if defined(__NO_SOCKETS)
      flags = TRIM(flags)//" no_sockets"
#endif
#if defined(__NO_MPI_THREAD_SUPPORT_CHECK)
      flags = TRIM(flags)//" no_mpi_thread_support_check"
#endif
#if defined(__NO_STATM_ACCESS)
      flags = TRIM(flags)//" no_statm_access"
#endif
#if defined(__MINGW)
      flags = TRIM(flags)//" mingw"
#endif
#if defined(__PW_CUDA_NO_HOSTALLOC)
      flags = TRIM(flags)//" pw_cuda_no_hostalloc"
#endif
#if defined(__STATM_RESIDENT)
      flags = TRIM(flags)//" statm_resident"
#endif
#if defined(__STATM_TOTAL)
      flags = TRIM(flags)//" statm_total"
#endif
#if defined(__PLUMED2)
      flags = TRIM(flags)//" plumed2"
#endif
#if defined(__HAS_IEEE_EXCEPTIONS)
      flags = TRIM(flags)//" has_ieee_exceptions"
#endif
#if defined(__NO_ABORT)
      flags = TRIM(flags)//" no_abort"
#endif
#if defined(__SPGLIB)
      flags = TRIM(flags)//" spglib"
#endif
#if defined(__ACCELERATE)
      flags = TRIM(flags)//" accelerate"
#endif
#if defined(__MKL)
      flags = TRIM(flags)//" mkl"
#endif
#if defined(__DFTD4)
      flags = TRIM(flags)//" libdftd4"
#endif
#if defined(__TBLITE)
      flags = TRIM(flags)//" mctc-lib"
      flags = TRIM(flags)//" tblite"
#endif
#if defined(__SIRIUS)
      flags = TRIM(flags)//" sirius"
#endif
#if defined(__SIRIUS_NLCG)
      flags = TRIM(flags)//" sirius_nlcg"
#endif
#if defined(__SIRIUS_DFTD4)
      flags = TRIM(flags)//" sirius_dftd4"
#endif
#if defined(__SIRIUS_VCSQNM)
      flags = TRIM(flags)//" sirius_vcsqnm"
#endif
#if defined(__CHECK_DIAG)
      flags = TRIM(flags)//" check_diag"
#endif
#if defined(__LIBVORI)
      flags = TRIM(flags)//" libvori"
      flags = TRIM(flags)//" libbqb"
#endif
#if defined(__LIBMAXWELL)
      flags = TRIM(flags)//" libmaxwell"
#endif
#if defined(__LIBTORCH)
      flags = TRIM(flags)//" libtorch"
#endif
#if defined(__OFFLOAD_CUDA)
      flags = TRIM(flags)//" offload_cuda"
#endif
#if defined(__OFFLOAD_HIP)
      flags = TRIM(flags)//" offload_hip"
#endif
#if defined(__OFFLOAD_OPENCL)
      flags = TRIM(flags)//" offload_opencl"
#endif
#if defined(__NO_OFFLOAD_GRID)
      flags = TRIM(flags)//" no_offload_grid"
#endif
#if defined(__NO_OFFLOAD_DBM)
      flags = TRIM(flags)//" no_offload_dbm"
#endif
#if defined(__NO_OFFLOAD_PW)
      flags = TRIM(flags)//" no_offload_pw"
#endif
#if defined(__OFFLOAD_PROFILING)
      flags = TRIM(flags)//" offload_profiling"
#endif

#if defined(__SPLA) && defined(__OFFLOAD_GEMM)
      flags = TRIM(flags)//" spla_gemm_offloading"
#endif

#if defined(__CUSOLVERMP)
      flags = TRIM(flags)//" cusolvermp"
#endif

#if defined(__DLAF)
      flags = TRIM(flags)//" dlaf"
#endif

#if defined(__LIBVDWXC)
      flags = TRIM(flags)//" libvdwxc"
#endif

#if defined(__HDF5)
      flags = TRIM(flags)//" hdf5"
#endif

#if defined(__TREXIO)
      flags = TRIM(flags)//" trexio"
#endif

#if defined(__OFFLOAD_UNIFIED_MEMORY)
      flags = TRIM(flags)//" offload_unified_memory"
#endif

#if defined(__SMEAGOL)
      flags = TRIM(flags)//" libsmeagol"
#endif

#if defined(__GREENX)
      flags = TRIM(flags)//" greenx"
#endif

   END FUNCTION cp2k_flags

! **************************************************************************************************
!> \brief ...
!> \param iunit ...
! **************************************************************************************************
   SUBROUTINE print_cp2k_license(iunit)

      INTEGER                                            :: iunit

      WRITE (UNIT=iunit, FMT="(T2,A)") &
         "******************************************************************************", &
         "*                                                                            *", &
         "*   CP2K: A general program to perform molecular dynamics simulations        *", &
         "*   Copyright (C) 2000-2025  CP2K developer group <https://www.cp2k.org/>    *", &
         "*                                                                            *", &
         "*   This program is free software: you can redistribute it and/or modify     *", &
         "*   it under the terms of the GNU General Public License as published by     *", &
         "*   the Free Software Foundation, either version 2 of the License, or        *", &
         "*   (at your option) any later version.                                      *", &
         "*                                                                            *", &
         "*   This program is distributed in the hope that it will be useful,          *", &
         "*   but WITHOUT ANY WARRANTY; without even the implied warranty of           *", &
         "*   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the            *", &
         "*   GNU General Public License for more details.                             *", &
         "*                                                                            *", &
         "*   You should have received a copy of the GNU General Public License        *", &
         "*   along with this program.  If not, see <https://www.gnu.org/licenses/>.   *", &
         "*                                                                            *", &
         "******************************************************************************"

   END SUBROUTINE print_cp2k_license

! **************************************************************************************************
!> \brief ...
! **************************************************************************************************
   SUBROUTINE get_runtime_info()

      r_datx = ""
      r_cwd = ""
      r_host_name = ""
      r_user_name = ""
      r_pid = -1

      CALL m_getpid(r_pid)
      CALL m_getlog(r_user_name)
      CALL m_hostnm(r_host_name)
      CALL m_datum(r_datx)
      CALL m_getcwd(r_cwd)

   END SUBROUTINE

! **************************************************************************************************
!> \brief Writes the header for the restart file
!> \param iunit ...
!> \par History
!>      01.2008 [created] - Split from write_restart
!> \author Teodoro Laino - University of Zurich - 01.2008
! **************************************************************************************************
   SUBROUTINE write_restart_header(iunit)
      INTEGER, INTENT(IN)                                :: iunit

      CHARACTER(LEN=256)                                 :: cwd, datx

      CALL m_datum(datx)
      CALL m_getcwd(cwd)

      WRITE (UNIT=iunit, FMT="(T2,A)") "# Version information for this restart file "
      WRITE (UNIT=iunit, FMT="(T2,A)") "# current date "//TRIM(datx)
      WRITE (UNIT=iunit, FMT="(T2,A)") "# current working dir "//TRIM(cwd)

      WRITE (UNIT=iunit, FMT="(T2,A,T31,A50)") &
         "# Program compiled at", &
         ADJUSTR(compile_date(1:MIN(50, LEN(compile_date))))
      WRITE (UNIT=iunit, FMT="(T2,A,T31,A50)") &
         "# Program compiled on", &
         ADJUSTR(compile_host(1:MIN(50, LEN(compile_host))))
      WRITE (UNIT=iunit, FMT="(T2,A,T31,A50)") &
         "# Program compiled for", &
         ADJUSTR(compile_arch(1:MIN(50, LEN(compile_arch))))
      WRITE (UNIT=iunit, FMT="(T2,A,T31,A50)") &
         "# Source code revision number", &
         ADJUSTR(compile_revision)

   END SUBROUTINE write_restart_header

END MODULE cp2k_info
