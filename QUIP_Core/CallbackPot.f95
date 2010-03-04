!XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
!XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
!X
!X     QUIP: quantum mechanical and interatomic potential simulation package
!X
!X     Portions written by Noam Bernstein, while working at the
!X     Naval Research Laboratory, Washington DC.
!X
!X     Portions written by Gabor Csanyi, Copyright 2006-2007.
!X
!X     When using this software,  please cite the following reference:
!X
!X     reference
!X
!XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
!XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
!X
!X Callbackpot Module
!X
!% Callbackpot is a potential that computes things by writing atomic config to a
!% file, running a command, and reading its output
!%
!% it takes an argument string on initialization with one mandatory parameter
!%>   command=path_to_command
!% and two optional parameters
!%>   property_list=prop1:T1:N1:prop2:T2:N2...
!% which defaults to 'pos', and
!%>   min_cutoff=cutoff
!% which default to zero. If min_cutoff is non zero and the cell is narrower
!% than $2*min_cutoff$ in any direction then it will be replicated before
!% being written to the file. The forces are taken from the primitive cell
!% and the energy is reduced by a factor of the number of repeated copies.
!% 
!% The command takes 2 arguments, the names of the input and the output files.
!% command output is in extended xyz form.
!%
!% energy and virial (both optional) are passed via the comment, labeled as
!%     'energy=E' and 'virial="vxx vxy vxz vyx vyy vyz vzx vzy vzz"'.
!%
!%  per atoms data is at least atomic type and optionally 
!%     a local energy (labeled 'local_e:R:1') 
!%  and 
!%  forces (labeled 'force:R:3')
!%
!% right now (14/2/2008) the atoms_xyz reader requires the 1st 3 columns after
!%   the atomic type to be the position.
!% 
!% If you ask for some quantity from Callbackpot_Calc and it's not in the output file, it
!% returns an error status or crashes (if err isn't present).
!X
!XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
!XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
! some day implement calculation queues
! how to do this? one possibility:
!  add args_str to Callbackpot_Calc, and indicate
!   queued_force=i to indicate this atoms structure should be queued for the calculation
!    of forces on atom i (or a list, or a range?)
! or
!   process_queue, which would process the queue and fill in all the forces
module Callbackpot_module

use libatoms_module
use mpi_context_module

implicit none
private

integer, parameter :: MAX_CALLBACKS = 20
integer :: n_callbacks = 0

public :: Callbackpot_type
type CallbackPot_type
   character(len=1024) :: init_args_str
   integer :: callback_id
   type(MPI_context) :: mpi
end type CallbackPot_type

public :: Initialise
interface Initialise
  module procedure Callbackpot_Initialise
end interface Initialise

public :: Finalise
interface Finalise
  module procedure Callbackpot_Finalise
end interface Finalise

public :: cutoff
interface cutoff
   module procedure Callbackpot_cutoff
end interface

public :: Wipe
interface Wipe
  module procedure Callbackpot_Wipe
end interface Wipe

public :: Print
interface Print
  module procedure Callbackpot_Print
end interface Print

public :: calc
interface calc
  module procedure Callbackpot_Calc
end interface

public :: set_callback
interface set_callback
   module procedure callbackpot_set_callback
end interface


interface 
   subroutine register_callbackpot_sub(sub)
     interface 
        subroutine sub(at, calc_energy, calc_local_e, calc_force, calc_virial)
          integer, intent(in) :: at(12)
          logical :: calc_energy, calc_local_e, calc_force, calc_virial
        end subroutine sub
     end interface
   end subroutine register_callbackpot_sub
end interface
  
interface 
   subroutine call_callbackpot_sub(i,at, calc_energy, calc_local_e, calc_force, calc_virial)
     integer, intent(in) :: i
     integer, intent(in) :: at(12)
     logical :: calc_energy, calc_local_e, calc_force, calc_virial
   end subroutine call_callbackpot_sub
end interface


contains


subroutine Callbackpot_Initialise(this, args_str, mpi)
  type(Callbackpot_type), intent(inout) :: this
  character(len=*), intent(in) :: args_str
  type(MPI_Context), intent(in), optional :: mpi

  call finalise(this)
  this%init_args_str = args_str
  if (present(mpi)) this%mpi = mpi

end subroutine Callbackpot_Initialise

subroutine callbackpot_set_callback(this, callback)
  type(Callbackpot_type), intent(inout) :: this
  interface
     subroutine callback(at, calc_energy, calc_local_e, calc_force, calc_virial)
       integer, intent(in) :: at(12)
       logical :: calc_energy, calc_local_e, calc_force, calc_virial
     end subroutine callback
  end interface

  if (n_callbacks >= MAX_CALLBACKS) &
       call system_abort('CallbackPot_Initialise: Too many registered callback routines')
  this%callback_id = n_callbacks
  n_callbacks = n_callbacks + 1
  call register_callbackpot_sub(callback)

end subroutine Callbackpot_Set_callback

subroutine Callbackpot_Finalise(this)
  type(Callbackpot_type), intent(inout) :: this

  call wipe(this)

end subroutine Callbackpot_Finalise

subroutine Callbackpot_Wipe(this)
  type(Callbackpot_type), intent(inout) :: this

  this%callback_id = -1

end subroutine Callbackpot_Wipe

function Callbackpot_cutoff(this)
  type(Callbackpot_type), intent(in) :: this
  real(dp) :: Callbackpot_cutoff
  Callbackpot_cutoff = 0.0_dp ! return zero, because Callbackpot does its own connection calculation
end function Callbackpot_cutoff

subroutine Callbackpot_Print(this, file)
  type(Callbackpot_type),    intent(in)           :: this
  type(Inoutput), intent(inout),optional,target:: file

  if (current_verbosity() < NORMAL) return

  call print("Callbackpot: callback_id='"//this%callback_id)

end subroutine Callbackpot_Print

subroutine Callbackpot_Calc(this, at, energy, local_e, forces, virial, args_str, err)
  type atoms_ptr_type
     type(atoms), pointer :: p
  end type atoms_ptr_type
  type(Callbackpot_type), intent(inout) :: this
  type(Atoms), intent(inout) :: at
  real(dp), intent(out), optional :: energy
  real(dp), intent(out), target, optional :: local_e(:)
  real(dp), intent(out), optional :: forces(:,:)
  real(dp), intent(out), optional :: virial(3,3)
  character(len=*), intent(in), optional :: args_str
  integer, intent(out), optional :: err
  type(Atoms), target :: at_copy
  type(atoms_ptr_type) :: at_ptr
  integer :: at_ptr_i(12)
  real(dp), pointer :: local_e_ptr(:), force_ptr(:,:)
  logical :: calc_energy, calc_local_e, calc_force, calc_virial
  
  calc_energy = .false.
  calc_local_e = .false.
  calc_force = .false.
  calc_virial = .false.
  if (present(energy)) then
     energy = 0.0_dp
     calc_energy = .true.
  end if
  if (present(local_e)) then
     local_e = 0.0_dp
     calc_local_e = .true.
  end if
  if (present(forces)) then
     forces = 0.0_dp
     calc_force = .true.
  end if
  if (present(virial)) then
     virial = 0.0_dp
     calc_virial = .true.
  end if
  if (present(err)) err = 0

  if (this%callback_id < 0) call system_abort('callbackpot_calc: callback_id < 0')

  at_copy = at
  at_ptr%p => at_copy
  at_ptr_i = transfer(at_ptr, at_ptr_i)
  call call_callbackpot_sub(this%callback_id, at_ptr_i, calc_energy, calc_local_e, calc_force, calc_virial)

  if (present(energy)) then
     if (.not. get_value(at_copy%params, 'energy', energy)) &
          call print('WARNING Callbackpot_calc: "energy" requested but not returned by callback')
  end if

  if (present(local_e)) then
     if (.not. assign_pointer(at_copy, 'local_e', local_e_ptr)) then
        call print('WARNING Callbackpot_calc: "local_e" requested but not returned by callback')
     else
        local_e(:) = local_e_ptr
     end if
  end if

  if (present(forces)) then
     if (.not. assign_pointer(at_copy, 'force', force_ptr)) then
        call print('WARNING Callbackpot_calc: "forces" requested but not returned by callback')
     else
        forces(:,:) = force_ptr
     end if
  end if

  if (present(virial)) then
     if (.not. get_value(at_copy%params, 'virial', virial)) &
          call print('Callbackpot_calc: "virial" requested but not returned by callback')
  end if

  if (this%mpi%active) then
     ! Share results with other nodes
     if (present(energy))  call bcast(this%mpi, energy)
     if (present(local_e)) call bcast(this%mpi, local_e)

     if (present(forces))  call bcast(this%mpi, forces)
     if (present(virial))  call bcast(this%mpi, virial)
  end if

end subroutine Callbackpot_calc

end module Callbackpot_module
