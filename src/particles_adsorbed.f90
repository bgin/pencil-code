! $Id: particles_adsorbed.f90 21950 2014-07-08 08:53:00Z jonas.kruger $
!
!  This module takes care of everything related to reactive particles.
!
!** AUTOMATIC CPARAM.INC GENERATION ****************************
!
! Declare (for generation of cparam.inc) the number of f array
! variables and auxiliary variables added by this module
!
! MAUX CONTRIBUTION 0
!
! CPARAM logical, parameter :: lparticles_adsorbed=.true.
!
!  PENCILS PROVIDED theta(nadsspec)
!
!***************************************************************
module Particles_adsorbed
!
  use Cdata
  use Cparam
  use General, only: keep_compiler_quiet
  use Messages
  use Particles_cdata
  use Particles_mpicomm
  use Particles_sub
  use Particles_chemistry
  use SharedVariables
!
  implicit none
!
  include 'particles_adsorbed.h'
!
!*****************************************************************
! Particle number independent variables
!*****************************************************************
!
  real, dimension(:), allocatable :: site_occupancy
  character(len=labellen), dimension(ninit) :: init_adsorbed='nothing'
  character(len=10), dimension(50) :: adsorbed_species_names
  real, dimension(10) :: init_surf_ads_frac
  real, dimension(:,:), allocatable :: mu_power
  real :: init_thCO=0.0
  real :: adsplaceholder=0.0
  real :: sum_ads
  real :: dpads=0.0
  logical :: lexperimental_adsorbed=.false.
  integer, dimension(:), allocatable :: idiag_ads
!
!*********************************************************************!
!               Particle dependent variables below here               !
!*********************************************************************!
!
  namelist /particles_ads_init_pars/ &
      init_adsorbed, &
      init_surf_ads_frac, &
      lexperimental_adsorbed, &
      dpads
!
  namelist /particles_ads_run_pars/ adsplaceholder
!
  contains
!***********************************************************************
    subroutine register_particles_ads()
!
!  this is a wrapper function for registering particle number
!  in- and independent variables
!
      if (lroot) call svn_id( &
          "$Id: particles_adsorbed.f90 20849 2014-10-06 18:45:43Z jonas.kruger $")
!
      call register_indep_ads()
      call register_dep_ads()
!
    endsubroutine register_particles_ads
!***********************************************************************
    subroutine register_indep_ads()
!
!  Set up indices for access to the fp and dfp arrays
!
!  29-aug-14/jonas: coded
!
      use FArrayManager, only: farray_register_auxiliary
!
      integer :: i, stat,j
      character(len=10), dimension(40) :: reactants
!
!  check if enough storage was reserved in fp and dfp to store
!  the adsorbed species surface and gas phase surface concentrations
!
      if (nadsspec /= (N_adsorbed_species-1) .and. N_adsorbed_species > 1) then
        print*,'N_adsorbed_species: ',N_adsorbed_species-1
        print*,'nadsspec: ',nadsspec
        call fatal_error('register_particles_ads', &
            'wrong size of storage for adsorbed species allocated.')
      endif
!
      if (N_adsorbed_species > 1) then
        call create_ad_sol_lists(adsorbed_species_names,'ad')
        call get_reactants(reactants)
        call sort_compounds(reactants,adsorbed_species_names,N_adsorbed_species)
      endif
!
!  Set some indeces (this is hard-coded for now)
!
      if (N_adsorbed_species > 1) then
        imuadsO = find_species('C(O)',adsorbed_species_names,N_adsorbed_species)
        imuadsO2 = find_species('C2(O2)',adsorbed_species_names,N_adsorbed_species)
        imuadsOH = find_species('C(OH)',adsorbed_species_names,N_adsorbed_species)
        imuadsH = find_species('C(H)',adsorbed_species_names,N_adsorbed_species)
        imuadsCO = find_species('C(CO)',adsorbed_species_names,N_adsorbed_species)
        imufree = find_species('Cf',adsorbed_species_names,N_adsorbed_species)
      endif
!
!  Indices of adsorbed species mole fraction
!
      if (N_adsorbed_species > 1) then
        j = 1
        iads = npvar+1
        i = 1
!
        do while (i <= (N_adsorbed_species-1))
          if (adsorbed_species_names(i) /= 'Cf') then
            pvarname(iads+j-1) = 'i'//adsorbed_species_names(i)
            i = i+1
            j = j+1
          else
            i = i+1
          endif
        enddo
!
!  Increase of npvar according to N_adsorbed_species
!  The -2 is there to account for Cf being in adsorbed_species_names
!  but not in the calculation
!
        npvar = npvar+N_adsorbed_species-1
        iads_end = iads+N_adsorbed_species-2
      endif
!
!  Check that the fp and dfp arrays are big enough.
!
      if (npvar > mpvar) then
        if (lroot) write (0,*) 'npvar = ', npvar, ', mpvar = ', mpvar
        call fatal_error('register_ads','npvar > mpvar')
      endif
!
!  Allocate only if adsorbed species in mechanism
!
!      print*,'Number of adsorbed species: ', N_adsorbed_species
!
      if (N_adsorbed_species > 1) then
        allocate(mu(N_adsorbed_species,N_surface_reactions),STAT=stat)
        if (stat > 0) call fatal_error('register_indep_ads', &
            'Could not allocate memory for mu')
        allocate(mu_prime(N_adsorbed_species,N_surface_reactions),STAT=stat)
        if (stat > 0) call fatal_error('register_indep_ads', &
            'Could not allocate memory for mu_prime')
        allocate(aac(N_adsorbed_species),STAT=stat)
        if (stat > 0) call fatal_error('register_indep_ads', &
            'Could not allocate memory for aac')
        allocate(site_occupancy(N_adsorbed_species),STAT=stat)
        if (stat > 0) call fatal_error('register_indep_ads', &
            'Could not allocate memory for site_occupancy')
        allocate(mu_power(N_adsorbed_species,N_surface_reactions),STAT=stat)
        if (stat > 0) call fatal_error('register_indep_ads', &
            'Could not allocate memory for mu_power')
        allocate(idiag_ads(N_adsorbed_species),STAT=stat)
        if (stat > 0) call fatal_error('register_indep_ads', &
            'Could not allocate memory for idiag_ads')
        idiag_ads = 0
      endif
!
! Define the aac array which gives the amount of carbon in the
! adsorbed species.
!
      if (N_adsorbed_species > 1) then
        aac = 0
        if (imuadsCO > 0) aac(imuadsCO) = 1
      endif
!
      if (N_adsorbed_species > 1) then
        call create_stoc(adsorbed_species_names,mu,.true., &
            N_adsorbed_species,mu_power)
        call create_stoc(adsorbed_species_names,mu_prime,.false., &
            N_adsorbed_species)
        call create_occupancy(adsorbed_species_names,site_occupancy)
!
      endif
    endsubroutine register_indep_ads
!***********************************************************************
    subroutine register_dep_ads()
!
      integer :: stat
!
      stat = 0
!
    endsubroutine register_dep_ads
!***********************************************************************
    subroutine initialize_particles_ads(f)
!
!  Perform any post-parameter-read initialization i.e. calculate derived
!  parameters.
!
!  29-aug-14/jonas coded
!
      real, dimension(mx,my,mz,mfarray) :: f
!
      call keep_compiler_quiet(f)
!
    endsubroutine initialize_particles_ads
!***********************************************************************
    subroutine init_particles_ads(f,fp)
!
!  Initial particle surface fractions
!
!  01-sep-14/jonas: coded
!
      real, dimension(mx,my,mz,mfarray) :: f
      real, dimension(mpar_loc,mparray) :: fp
      integer :: j,i
!
      intent(out) :: f, fp
!
      call keep_compiler_quiet(f)
!
      if (N_adsorbed_species > 1) then
        fp(:,iads:iads_end) = 0.
        do j = 1,ninit
!
!  Writing the initial adsorbed species fractions
!
          select case (init_adsorbed(j))
          case ('nothing')
            if (lroot .and. j == 1) print*, 'init_particles_ads,adsorbed: nothing'
          case ('constant')
            if (lroot) print*, 'init_particles_ads: Initial Adsorbed Fractions'
            sum_ads = sum(init_surf_ads_frac(1:N_adsorbed_species))
!
!  This ensures that we don't have unphysical values as init
!
            if (sum_ads > 1.) then
              print*, 'sum of init_surf_ads_frac > 1, normalizing...'
              init_surf_ads_frac(1:N_adsorbed_species) = &
                  init_surf_ads_frac(1:N_adsorbed_species) / sum_ads
            endif
!
            do i = 1,mpar_loc
              fp(i,iads:iads_end) = init_surf_ads_frac(1:(iads_end-iads+1))
            enddo
          case default
            if (lroot) &
                print*, 'init_particles_ads: No such such value for init_adsorbed: ', &
                trim(init_adsorbed(j))
            call fatal_error('init_particles_ads','')
          endselect
        enddo
      else
      endif
!
    endsubroutine init_particles_ads
!***********************************************************************
    subroutine pencil_criteria_par_ads()
!
!  All pencils that the Particles_adsorbed
!  module depends on are specified here.
!
!  01-sep-14/jonas: coded
!
    endsubroutine pencil_criteria_par_ads
!***********************************************************************
    subroutine dpads_dt(f,df,fp,dfp,ineargrid)
!
!  Evolution of particle surface fractions.
!
!  01-sep-14/jonas: coded
!
      real, dimension(mx,my,mz,mfarray) :: f
      real, dimension(mx,my,mz,mvar) :: df
      real, dimension(mpar_loc,mparray) :: fp
      real, dimension(mpar_loc,mpvar) :: dfp
      integer, dimension(mpar_loc,3) :: ineargrid
      integer :: i
!
      call keep_compiler_quiet(f)
      call keep_compiler_quiet(df)
!     call keep_compiler_quiet(fp)
      call keep_compiler_quiet(dfp)
      call keep_compiler_quiet(ineargrid)
!
      if (ldiagnos) then
        do i = 1,N_adsorbed_species
          if (idiag_ads(i) /= 0) then
            call sum_par_name(fp(1:npar_loc,iads+i-1),idiag_ads(i))
          endif
        enddo
      endif
!
    endsubroutine dpads_dt
!***********************************************************************
    subroutine dpads_dt_pencil(f,df,fp,dfp,p,ineargrid)
!
!  Evolution of particle surface fractions
!
!  03-sep-14/jonas: coded
!
      real, dimension(mx,my,my,mfarray) :: f
      real, dimension(mx,my,mz,mvar) :: df
      real, dimension(mpar_loc,mparray) :: fp
      real, dimension(mpar_loc,mpvar) :: dfp
      real, dimension(:), allocatable :: mod_surf_area, R_c_hat
      real, dimension(:,:), allocatable :: R_j_hat
      type (pencil_case) :: p
      integer, dimension(mpar_loc,3) :: ineargrid
      integer :: n_ads, stat, k1, k2, k, ierr
      real, pointer :: total_carbon_sites
!
      intent(inout) :: dfp
      intent(in) :: fp
!
      if (npar_imn(imn) /= 0) then
!
        k1 = k1_imn(imn)
        k2 = k2_imn(imn)
        n_ads = iads_end - iads +1
!
        if (N_adsorbed_species > 1) then
          allocate(mod_surf_area(k1:k2))
          allocate(R_c_hat(k1:k2))
          allocate(R_j_hat(k1:k2,1:n_ads))
          call calc_get_mod_surf_area(mod_surf_area,fp)
          call get_shared_variable('total_carbon_sites',total_carbon_sites,ierr)
          call get_adsorbed_chemistry(R_j_hat,R_c_hat)
          if (ierr /= 0) call fatal_error('dpads_dt_pencil', 'unable to get total_carbon')
          do k = k1,k2
            dfp(k,iads:iads_end) = R_j_hat(k,1:n_ads)/ &
                total_carbon_sites + mod_surf_area(k)* &
                R_c_hat(k)*fp(k,iads:iads_end)
          enddo
          deallocate(mod_surf_area)
          deallocate(R_c_hat)
          deallocate(R_j_hat)
        endif
      endif
!
    endsubroutine dpads_dt_pencil
!***********************************************************************
    subroutine read_particles_ads_init_pars(iostat)
!
      use File_io, only: get_unit
!
      integer, intent(out) :: iostat
      include "parallel_unit.h"
!
      read(parallel_unit, NML=particles_ads_init_pars, IOSTAT=iostat)
!
    endsubroutine read_particles_ads_init_pars
!***********************************************************************
    subroutine write_particles_ads_init_pars(unit)
!
      integer, intent(in) :: unit
!
      write(unit, NML=particles_ads_init_pars)
!
    endsubroutine write_particles_ads_init_pars
!***********************************************************************
    subroutine read_particles_ads_run_pars(iostat)
!
      use File_io, only: get_unit
!
      integer, intent(out) :: iostat
      include "parallel_unit.h"
!
      read(parallel_unit, NML=particles_ads_run_pars, IOSTAT=iostat)
!
    endsubroutine read_particles_ads_run_pars
!***********************************************************************
    subroutine write_particles_ads_run_pars(unit)
!
      integer, intent(in) :: unit
!
      write(unit, NML=particles_ads_run_pars)
!
    endsubroutine write_particles_ads_run_pars
!***********************************************************************
    subroutine rprint_particles_ads(lreset,lwrite)
!
!  Read and register print parameters relevant for
!  particles coverage fraction.
!
!  06-oct-14/jonas: adapted
!
      use Diagnostics
!
      logical :: lreset
      logical, optional :: lwrite
!
      logical :: lwr
      integer :: iname,i
      character(len=6) :: diagn_ads, number
!
!  Write information to index.pro
!
      lwr = .false.
      if (present(lwrite)) lwr = lwrite
      if (lwr) write (3,*) 'iads=', iads
!
      if (lreset) then
        idiag_ads = 0
      endif
!
      if (lroot .and. ip < 14) print*,'rprint_particles_ads: run through parse list'
!
      do iname = 1,nname
        do i = 1,N_adsorbed_species
          write (number,'(I2)') i
          diagn_ads = 'Yads'//trim(adjustl(number))
          call parse_name(iname,cname(iname),cform(iname),trim(diagn_ads),idiag_ads(i))
        enddo
      enddo
!
    endsubroutine rprint_particles_ads
!***********************************************************************
    subroutine particles_ads_prepencil_calc(f)
!
!  28-aug-14/jonas+nils: coded
!
      real, dimension(mx,my,mz,mfarray), intent(inout) :: f
!
      call keep_compiler_quiet(f)
!
    endsubroutine particles_ads_prepencil_calc
!***********************************************************************
    subroutine particles_adsorbed_clean_up()
!
      if (allocated(mu)) deallocate(mu)
      if (allocated(mu_prime)) deallocate(mu_prime)
      if (allocated(aac)) deallocate(aac)
      if (allocated(site_occupancy)) deallocate(site_occupancy)
      if (allocated(mu_power)) deallocate(mu_power)
      if (allocated(idiag_ads)) deallocate(idiag_ads)
!
    endsubroutine particles_adsorbed_clean_up
!***********************************************************************
endmodule Particles_adsorbed
