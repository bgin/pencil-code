! $Id: run.f90,v 1.46 2002-06-15 11:29:35 brandenb Exp $
!
!***********************************************************************
      program run
!
!  solve the isothermal hydro equation in 3-D
!
!-----------------------------------------------------------------------
!   1-apr-01/axel+wolf: coded
!  17-aug-01/axel: ghost layers implemented
!  11-sep-01/axel: adapted from burgers_phi
!
        use Cdata
        use General
        use Mpicomm
        use Sub
        use Register
        use Global
        use Param_IO
        use Equ
        use Slices
        use Print
        use Timestep
        use Wsnaps
!
        implicit none
!
        real, dimension (mx,my,mz,mvar) :: f,df
        integer :: time1,time2,count,count_rate
        logical :: stop=.false.,reload=.false.
        real :: Wall_clock_time
!
!  initialize MPI
!
!       call siginit
!       call signonbrutal
!
!  initialize MPI and register physics modules
!  (must be done before lroot can be used, for example)
!
        call initialize
!
!  identify version
!
        if (lroot) call cvs_id( &
             "$RCSfile: run.f90,v $", &
             "$Revision: 1.46 $", &
             "$Date: 2002-06-15 11:29:35 $")
!
!  ix,iy,iz are indices for checking variables at some selected point
!  set default values
!
        ix=mx/2; iy=my/2; iz=mz/2
        dtmin=1e-6  !!(AB: this should be an input parameter, better dimless)
!
!  read parameters and output parameter list
!
        call rparam !(Read parameters from start.x; may be overwritten by
                    ! read_runpars)
        call read_runpars(PRINT=.true.)
        call rprint_list(.false.)
!
!  read data
!  snapshot data are saved in the tmp subdirectory.
!  This directory must exist, but may be linked to another disk.
!
        if (ip<=6.and.lroot) print*,'reading var files'
        call input(trim(directory)//'/var.dat',f,mvar,1)
        call rglobal()      ! Read global variables (if there are)
!
!  read coordinates
!
        if (ip<=6.and.lroot) print*,'reading grid coordinates'
        call rgrid(trim(directory)//'/grid.dat')
!
!  read seed field parameters (only if forcing is turned on)
!
        if (lforcing) then
          if (lroot.and.ip<14) print*,'reading seed file'
          call inpui(trim(directory)//'/seed.dat',seed,2)
          call random_seed(put=seed)
        endif
!
!  advance equations
!  NOTE: headt=.true. in order to print header titles
!
        headt=.true.
        if(lroot) then
          call system_clock(count_rate=count_rate)
          call system_clock(count=time1)
          count = 0
        endif
!
!  do loop in time
!
        Time_loop: do it=1,nt
          lout=mod(it-1,it1).eq.0
          if (lout) then
            inquire(FILE="STOP", EXIST=stop) !(exit DO loop if the file `STOP' exists)
            if (stop.or.t>tmax) then
              if (lroot.and.stop) write(0,*) "done: found STOP file"
              if (lroot.and.t>tmax) write(0,*) "done: t > tmax"
              exit Time_loop
            endif
!
!  Re-read parameters if a file `RELOAD' has appeared
!
            inquire(FILE="RELOAD", EXIST=reload)
            if (reload) then
              if (lroot) write(0,*) "Found RELOAD file -- reloading parameters"
              call read_runpars(PRINT=.true.) !(Re-read configuration)
              call rprint_list(.true.) !(Re-read output list)
              call remove_file("RELOAD")
              reload = .false.
            endif
          endif
!
!  remove wiggles in lnrho in sporadic time intervals
!  This is necessary if the Reynolds number is large.
!  iwig=500 is a typical value. For iwig=0 no action is taken.
!  (These two queries must come separately on compaq machines.)
!
        if (iwig/=0) then; if (mod(it,iwig).eq.0) call rmwig(f); endif
!
!  time advance
!
          call rk_2n(f,df)
          count = count + 1     !  reliable loop count even for premature exit
          if (lforcing) call addforce(f)
          if(lout) call write_xyaverages
          if(lout) call prints
          call wsnap(trim(directory)//'/VAR',f,.true.)
          call wvid(trim(directory))
!
!  save snapshot every isnap steps in case the run gets interrupted
!
          if (mod(it,isave).eq.0) call wsnap(trim(directory)//'/var.dat',f,.false.)
!
          headt=.false.
!          if (it>=nt) exit Time_loop
!          if (dt < dtmin) then
          if ((it < nt) .and. (dt < dtmin)) then
            write(0,*) 'Time step has become too short: dt = ', dt
            exit Time_loop
          endif
        enddo Time_loop
        if(lroot) call system_clock(count=time2)
!
!  write data at end of run for restart
!  dvar is written for analysis purposes only
!
        call wsnap(trim(directory)//'/var.dat',f,.false.)
        if (ip<=10) call wsnap(trim(directory)//'/dvar.dat',df,.false.)
!
!  write seed parameters (only if forcing is turned on)
!
        if (lforcing) then
          call random_seed(get=seed)
          call outpui(trim(directory)//'/seed.dat',seed,2)
        endif
!
!  print wall clock time and time per step and processor
!  for diagnostic purposes
!
        if(lroot) then
          Wall_clock_time=(time2-time1)/real(count_rate)
          print*
          print*,'Wall clock time [sec]=',Wall_clock_time,' (+/- ', 1./count_rate,')'
          if (it>1) print*, 'Wall clock time/timestep/meshpoint [microsec]=', &
               Wall_clock_time/count/nw/ncpus/1e-6
          print*
        endif
        call mpifinalize
!
      endprogram run


