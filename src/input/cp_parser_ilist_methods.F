!--------------------------------------------------------------------------------------------------!
!   CP2K: A general program to perform molecular dynamics simulations                              !
!   Copyright 2000-2025 CP2K developers group <https://cp2k.org>                                   !
!                                                                                                  !
!   SPDX-License-Identifier: GPL-2.0-or-later                                                      !
!--------------------------------------------------------------------------------------------------!

! **************************************************************************************************
!> \brief a module to allow simple internal preprocessing in input files.
!> \par History
!>      - standalone proof-of-concept implementation (20.02.2008,AK)
!>      - integration into cp2k (22.02.2008,tlaino)
!>      - variables added (25.02.2008,AK)
!> \author Axel Kohlmeyer [AK] - CMM/UPenn Philadelphia
!> \date 25.02.2008
! **************************************************************************************************
MODULE cp_parser_ilist_methods
   USE cp_log_handling,                 ONLY: cp_to_string
   USE cp_parser_ilist_types,           ONLY: ilist_type
#include "../base/base_uses.f90"

   IMPLICIT NONE
   PRIVATE

   PUBLIC :: ilist_setup, ilist_update, ilist_reset
   CHARACTER(len=*), PARAMETER, PRIVATE :: moduleN = 'cp_parser_ilist_methods'

CONTAINS

! ****************************************************************************
!> \brief setup the integer listing type
!> \param ilist ...
!> \param token ...
!> \date  08.2008
!> \author Teodoro Laino [tlaino] - University of Zurich
! **************************************************************************************************
   SUBROUTINE ilist_setup(ilist, token)
      TYPE(ilist_type), POINTER                          :: ilist
      CHARACTER(LEN=*)                                   :: token

      INTEGER                                            :: ind

      CPASSERT(ASSOCIATED(ilist))
      ind = INDEX(token, "..")
      READ (UNIT=token(:ind - 1), FMT=*) ilist%istart
      READ (UNIT=token(ind + 2:), FMT=*) ilist%iend
      IF (ilist%istart > ilist%iend) &
         CALL cp_abort(__LOCATION__, &
                       "Invalid list range specified: "// &
                       TRIM(ADJUSTL(cp_to_string(ilist%istart)))//".."// &
                       TRIM(ADJUSTL(cp_to_string(ilist%iend))))
      ilist%nel_list = ilist%iend - ilist%istart + 1
      ilist%ipresent = ilist%istart
      ilist%in_use = .TRUE.

   END SUBROUTINE ilist_setup

! ****************************************************************************
!> \brief updates the integer listing type
!> \param ilist ...
!> \date  08.2008
!> \author Teodoro Laino [tlaino] - University of Zurich
! **************************************************************************************************
   SUBROUTINE ilist_update(ilist)
      TYPE(ilist_type), POINTER                          :: ilist

      CPASSERT(ASSOCIATED(ilist))
      ilist%ipresent = ilist%ipresent + 1
      IF (ilist%ipresent > ilist%iend) THEN
         CALL ilist_reset(ilist)
      END IF
   END SUBROUTINE ilist_update

! ****************************************************************************
!> \brief updates the integer listing type
!> \param ilist ...
!> \date  08.2008
!> \author Teodoro Laino [tlaino] - University of Zurich
! **************************************************************************************************
   SUBROUTINE ilist_reset(ilist)
      TYPE(ilist_type), POINTER                          :: ilist

      CPASSERT(ASSOCIATED(ilist))
      IF (ilist%ipresent == ilist%iend) THEN
         ilist%istart = HUGE(0)
         ilist%iend = HUGE(0)
         ilist%nel_list = HUGE(0)
         ilist%ipresent = HUGE(0)
         ilist%in_use = .FALSE.
      END IF
   END SUBROUTINE ilist_reset

END MODULE cp_parser_ilist_methods
