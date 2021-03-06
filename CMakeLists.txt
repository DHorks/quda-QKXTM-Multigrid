# basic setup for cmake
cmake_minimum_required(VERSION 3.1 FATAL_ERROR)
set(CMAKE_INCLUDE_CURRENT_DIR ON)
set(CMAKE_INCLUDE_DIRECTORIES_PROJECT_BEFORE ON)
set(CMAKE_COLOR_MAKEFILE ON)
set(CMAKE_CXX_STANDARD_REQUIRED 11)
set(CMAKE_CXX_STANDARD 11)
# disable in source builds
# this is only a temporary fix, but for now we need it as cmake will
# otherwise overwrite the existing makefiles
set(CMAKE_DISABLE_SOURCE_CHANGES ON)
set(CMAKE_DISABLE_IN_SOURCE_BUILD ON)
# add a directory for cmake modules
list(APPEND CMAKE_MODULE_PATH "${CMAKE_SOURCE_DIR}/cmake")



find_package(Git)
SET(DEFBUILD "RELEASE")
IF(GIT_FOUND)
execute_process(COMMAND ${GIT_EXECUTABLE} show WORKING_DIRECTORY ${CMAKE_SOURCE_DIR} RESULT_VARIABLE IS_GIT_REPOSIITORY OUTPUT_QUIET ERROR_QUIET)
  IF(${IS_GIT_REPOSIITORY} EQUAL 0)
    execute_process(COMMAND ${GIT_EXECUTABLE} describe --abbrev=0 WORKING_DIRECTORY ${CMAKE_SOURCE_DIR} OUTPUT_VARIABLE GITTAG OUTPUT_STRIP_TRAILING_WHITESPACE)
# we use git rev-list and pipe that through wc here. Newer git versions support --count as option to rev-list but that might not always be available
    execute_process(COMMAND ${GIT_EXECUTABLE} rev-list ${GITTAG}..HEAD WORKING_DIRECTORY ${CMAKE_SOURCE_DIR} COMMAND wc -l OUTPUT_VARIABLE GITCOUNT OUTPUT_STRIP_TRAILING_WHITESPACE)
    execute_process(COMMAND ${GIT_EXECUTABLE}  describe --long --dirty WORKING_DIRECTORY ${CMAKE_SOURCE_DIR} OUTPUT_VARIABLE GITVERSION OUTPUT_STRIP_TRAILING_WHITESPACE)
    IF(GITCOUNT EQUAL 0)
      SET(DEFBUILD "RELEASE")
    ELSE()
      SET(DEFBUILD "DEVEL")
    ENDIF()
  ENDIF()
ENDIF(GIT_FOUND)

set(VALID_BUILD_TYPES DEVEL RELEASE STRICT DEBUG HOSTDEBUG DEVICEDEBUG )
SET(CMAKE_BUILD_TYPE "${DEFBUILD}" CACHE STRING  "Choose the type of build, options are: ${VALID_BUILD_TYPES}")
string(TOUPPER ${CMAKE_BUILD_TYPE} CHECK_BUILD_TYPE)
LIST(FIND VALID_BUILD_TYPES ${CHECK_BUILD_TYPE} BUILD_TYPE_VALID)

if(BUILD_TYPE_VALID LESS 0)
  message(SEND_ERROR "Please specify a valid CMAKE_BUILD_TYPE type! Valid build types are:" "${VALID_BUILD_TYPES}")
endif()


#
# PROJECT is QUDA
#
project("QUDA")

#######################################################################
# QUDA OPTIONS
# likely to be changed by users
#######################################################################
set(QUDA_GPU_ARCH sm_35 CACHE STRING "set the GPU architecture (sm_20, sm_21, sm_30, sm_35, sm_50, sm_52)")

# build options
set(QUDA_DIRAC_WILSON ON CACHE BOOL "build Wilson Dirac operators")
set(QUDA_DIRAC_CLOVER ON CACHE BOOL "build clover Dirac operators")
set(QUDA_DIRAC_DOMAIN_WALL ON CACHE BOOL "build domain wall Dirac operators")
set(QUDA_DIRAC_STAGGERED ON CACHE BOOL "build staggered Dirac operators")
set(QUDA_DIRAC_TWISTED_MASS ON CACHE BOOL "build twisted mass Dirac operators")
set(QUDA_DIRAC_TWISTED_CLOVER ON CACHE BOOL "build twisted clover Dirac operators")
set(QUDA_DIRAC_NDEG_TWISTED_MASS OFF CACHE BOOL "build non-degenerate twisted mass Dirac operators")
set(QUDA_LINK_ASQTAD OFF CACHE BOOL "build code for computing asqtad fat links")
set(QUDA_LINK_HISQ OFF CACHE BOOL "build code for computing hisq fat links")
set(QUDA_FORCE_GAUGE OFF CACHE BOOL "build code for (1-loop Symanzik) gauge force")
set(QUDA_FORCE_ASQTAD OFF CACHE BOOL "build code for asqtad fermion force")
set(QUDA_FORCE_HISQ OFF CACHE BOOL "build code for hisq fermion force")
set(QUDA_GAUGE_TOOLS OFF CACHE BOOL "build auxiliary gauge-field tools")
set(QUDA_GAUGE_ALG OFF CACHE BOOL "build gauge-fixing and pure-gauge algorithms")
set(QUDA_CONTRACT OFF CACHE BOOL "build code for bilinear contraction")
# Dynamic inversion saves memory but decreases the flops
set(QUDA_DYNAMIC_CLOVER OFF CACHE BOOL "Dynamically invert the clover term for twisted-clover")
set(QUDA_QIO OFF CACHE BOOL "build QIO code for binary I/O")

# Multi-GPU options
set(QUDA_QMP OFF CACHE BOOL "set to 'yes' to build the QMP multi-GPU code")
set(QUDA_MPI OFF CACHE BOOL "set to 'yes' to build the MPI multi-GPU code")
set(QUDA_POSIX_THREADS OFF CACHE BOOL "set to 'yes' to build pthread-enabled dslash")

#BLAS library
set(QUDA_MAGMA OFF CACHE BOOL "build magma interface")

#-C.K. Switch between Intel/MKL and GNU/OpenBlas
set(QUDA_QKXTM_INTEL-BUILD OFF CACHE BOOL "build QKXTM with Intel")
set(QUDA_QKXTM_GNU-BUILD OFF CACHE BOOL "build QKXTM with GNU")

# Interface options
set(QUDA_INTERFACE_QDP ON CACHE BOOL "build qdp interface")
set(QUDA_INTERFACE_MILC ON CACHE BOOL "build milc interface")
set(QUDA_INTERFACE_CPS OFF CACHE BOOL "build cps interface")
set(QUDA_INTERFACE_QDPJIT OFF CACHE BOOL "build qdpjit interface")
set(QUDA_INTERFACE_BQCD OFF CACHE BOOL "build bqcd interface")
set(QUDA_INTERFACE_TIFR OFF CACHE BOOL "build tifr interface")

#QKXTM: DMH
set(QUDA_INTERFACE_QKXTM ON CACHE BOOL "build QKXTM interface")
set(QUDA_QKXTM_ARPACK OFF CACHE BOOL "enable QKXTM ARPACK")

if(QUDA_INTERFACE_QKXTM)
  # Locations for GSL HDF5 LIME
  set(QUDA_QKXTM_GSLHOME "" CACHE PATH "path to GSL")
  set(QUDA_QKXTM_LIMEHOME "" CACHE PATH "path to LIME")
  set(QUDA_QKXTM_HDF5HOME "" CACHE PATH "path to HDF5")

#-C.K. Locations for OPENBLAS or MKL, depending on GNU/OpenBlas, Intel/MKL switches
  if(${QUDA_QKXTM_GNU-BUILD})
    set(QUDA_QKXTM_OPENBLAS_BUILD "" CACHE PATH "path to OPENBLAS_BUILD")
    set(QUDA_QKXTM_OPENBLAS_SRC "" CACHE PATH "path to OPENBLAS_SRC")
  endif()

#-C.K. In facts, it seems that these options do not really contribute something,
# but may be useful for future iterations
  if(${QUDA_QKXTM_INTEL-BUILD})
    set(QUDA_QKXTM_MKL_LIBDIR "" CACHE PATH "path to MKL library dir")
    set(QUDA_QKXTM_MKL_INCDIR "" CACHE PATH "path to MKL include dir")
  endif()
#-C.K.

  if(QUDA_QKXTM_ARPACK)
    set(QUDA_QKXTM_ARPACKHOME "" CACHE PATH "path to ARPACK")
  endif(QUDA_QKXTM_ARPACK)
endif(QUDA_INTERFACE_QKXTM)
#QKXTM: DMH

# QDPJIT
set(QUDA_QDPJIT OFF CACHE BOOL "build QDP-JIT support?")

# Locations for QIO / QMP
set(QUDA_QIOHOME "" CACHE PATH "path to QIO")
set(QUDA_QMPHOME "" CACHE PATH "path to QMP")

#######################################################################
#QUDA ADVANCED OPTIONS
# that ususally should not be changed by users
#######################################################################
set(QUDA_BLAS_TEX ON CACHE BOOL "enable texture reads in BLAS?")
set(QUDA_FERMI_DBLE_TEX ON CACHE BOOL "enable double-precision texture reads on Fermi?")
set(QUDA_NUMA_NVML OFF CACHE BOOL "experimental use of NVML to set numa affinity" )
set(QUDA_VERBOSE_BUILD OFF CACHE BOOL "display kernel register useage")

# NVTX options
set(QUDA_MPI_NVTX OFF CACHE BOOL "add nvtx markup to MPI API calls for the visual profiler")
set(QUDA_INTERFACE_NVTX OFF CACHE BOOL "add nvtx markup to interface calls for the visual profiler")

# GPUdirect options
set(QUDA_GPU_DIRECT ON CACHE BOOL "set to 'yes' to allow GPU and NIC to shared pinned buffers")
set(QUDA_GPU_COMMS OFF CACHE BOOL "set to 'yes' to allow GPU and NIC to communicate using RDMA")

# Packing option
set(QUDA_DEVICE_PACK ON CACHE BOOL "set to 'yes' to enable packing and unpacking on the device")

# features in development
set(QUDA_SSTEP OFF CACHE BOOL "build s-step linear solvers")
set(QUDA_MULTIGRID OFF CACHE BOOL "build multigrid solvers")
set(QUDA_BLOCKSOLVER OFF CACHE BOOL "build block solvers")

mark_as_advanced(QUDA_BLAS_TEX)
mark_as_advanced(QUDA_FERMI_DBLE_TEX)
mark_as_advanced(QUDA_NUMA_NVML)
mark_as_advanced(QUDA_VERBOSE_BUILD)

mark_as_advanced(QUDA_MPI_NVTX)
mark_as_advanced(QUDA_INTERFACE_NVTX)

mark_as_advanced(QUDA_GPU_DIRECT)
mark_as_advanced(QUDA_GPU_COMMS)

mark_as_advanced(QUDA_DEVICE_PACK)

mark_as_advanced(QUDA_SSTEP)
mark_as_advanced(QUDA_BLOCKSOVER)
mark_as_advanced(QUDA_MULTIGRID)

#######################################################################
# options that are not exposed at all because only one option exists
set(CPU_ARCH x86_64)


#######################################################################
# everything below here is processing the setup
#######################################################################

# we need to check for some packages
find_package(PythonInterp)

set(CUDA_HOST_COMPILER "${CMAKE_CXX_COMPILER}" CACHE FILEPATH "Host side compiler used by NVCC")
mark_as_advanced(CUDA_HOST_COMPILER)
find_package(CUDA REQUIRED)
find_package(Threads REQUIRED)

# do all the build definitions
#

if(${QUDA_MPI} OR ${QUDA_QMP})
  add_definitions(-DMULTI_GPU)
  find_package(MPI)
else()
  set(COMM_OBJS comm_single.cpp)
endif()

if(${QUDA_MPI})
  add_definitions(-DMPI_COMMS)
  set(COMM_OBJS comm_mpi.cpp)
  include_directories(SYSTEM ${MPI_CXX_INCLUDE_PATH})
endif()

if (${QUDA_QMP})
  add_definitions(-DQMP_COMMS)
  execute_process(COMMAND ${QUDA_QMPHOME}/bin/qmp-config --cflags OUTPUT_VARIABLE QMP_CFLAGS OUTPUT_STRIP_TRAILING_WHITESPACE)
  execute_process(COMMAND ${QUDA_QMPHOME}/bin/qmp-config --ldflags OUTPUT_VARIABLE QMP_LDFLAGS OUTPUT_STRIP_TRAILING_WHITESPACE)
  execute_process(COMMAND ${QUDA_QMPHOME}/bin/qmp-config --libs OUTPUT_VARIABLE QMP_LIBS OUTPUT_STRIP_TRAILING_WHITESPACE)
  FIND_LIBRARY(QMP_LIB qmp ${QUDA_QMPHOME}/lib)
  include_directories(SYSTEM ${QUDA_QMPHOME}/include)
  set(COMM_OBJS comm_qmp.cpp)
endif()

if (${QUDA_QIO})
  add_definitions(-DHAVE_QIO)
  set(QIO_UTIL qio_util.cpp qio_field.cpp layout_hyper.c)
  FIND_LIBRARY(QIO_LIB qio ${QUDA_QIOHOME}/lib/)
  FIND_LIBRARY(LIME_LIB lime ${QUDA_QIOHOME}/lib/)
  include_directories(SYSTEM ${QUDA_QIOHOME}/include)
endif()

if(QUDA_MAGMA)
  add_definitions(-DMAGMA_LIB -DADD_ -DMAGMA_SETAFFINITY -DGPUSHMEM=300 -DHAVE_CUBLAS -DMAGMA_LIB)
  find_package(PkgConfig REQUIRED)
  pkg_check_modules(MAGMA  magma)
  include_directories(SYSTEM ${MAGMA_INCLUDEDIR})
  message("${MAGMA_INCLUDEDIR}")
  find_package(OpenMP)
endif(QUDA_MAGMA)

#QKXTM: DMH
if(QUDA_INTERFACE_QKXTM)

  add_definitions(-DHAVE_GSL)
  FIND_LIBRARY(QKXTM_GSL_LIB gsl ${QUDA_QKXTM_GSLHOME}/lib)
  include_directories(SYSTEM ${QUDA_QKXTM_GSLHOME}/include/gsl)

  add_definitions(-DHAVE_HDF5)
  FIND_LIBRARY(QKXTM_HDF5_LIB hdf5 ${QUDA_QKXTM_HDF5HOME}/lib)
  include_directories(SYSTEM ${QUDA_QKXTM_HDF5HOME}/include)

  add_definitions(-DHAVE_LIME)
  FIND_LIBRARY(QKXTM_LIME_LIB lime ${QUDA_QKXTM_LIMEHOME}/lib)
  include_directories(SYSTEM ${QUDA_QKXTM_LIMEHOME}/include)

#-C.K. Modified here to take OpenBlas and MKL switches into account  
  if(${QUDA_QKXTM_GNU-BUILD})
    add_definitions(-DHAVE_OPENBLAS)
    FIND_LIBRARY(QKXTM_OPENBLAS_LIB openblas ${QUDA_QKXTM_OPENBLAS_BUILD}/lib)
    include_directories(SYSTEM ${QUDA_QKXTM_OPENBLAS_SRC})
  endif()

  if(${QUDA_QKXTM_INTEL-BUILD})
    add_definitions(-DHAVE_MKL)
    FIND_LIBRARY(QKXTM_MKL_LIB mkl_intel_lp64 ${QUDA_QKXTM_MKL_LIBDIR})
    include_directories(SYSTEM ${QUDA_QKXTM_MKL_INCDIR})
  endif()
#-C.K.

  include_directories(lib/code_pieces)
  include_directories(lib/code_pieces_Kepler)

  if(QUDA_QKXTM_ARPACK)
    add_definitions(-DHAVE_ARPACK)
    FIND_LIBRARY(QKXTM_PARPACK_LIB parpack  ${QUDA_QKXTM_ARPACKHOME})
    include_directories(SYSTEM ${QUDA_QKXTM_ARPACKHOME}/PARPACK/SRC/MPI)
    include_directories(SYSTEM ${QUDA_QKXTM_ARPACKHOME}/PARPACK/UTIL/MPI)
    
    FIND_LIBRARY(QKXTM_ARPACK_LIB arpack ${QUDA_QKXTM_ARPACKHOME})
    include_directories(SYSTEM ${QUDA_QKXTM_ARPACKHOME}/SRC)
    include_directories(SYSTEM ${QUDA_QKXTM_ARPACKHOME}/UTIL)
  endif(QUDA_QKXTM_ARPACK)
  
  LIST(APPEND QUDA_LIBS ${CUDA_cufft_LIBRARY} ${CUDA_curand_LIBRARY})

endif(QUDA_INTERFACE_QKXTM)
#QKXTM: DMH

if(QUDA_SSTEP)
  add_definitions(-DSSTEP)
endif()

if (QUDA_MULTIGRID)
  add_definitions(-DGPU_MULTIGRID)
endif(QUDA_MULTIGRID)

if(QUDA_BLOCKSOLVER)
  add_definitions(-DBLOCKSOLVER)
  find_package(Eigen REQUIRED)
  include_directories(${EIGEN_INCLUDE_DIRS})
  set(QUDA_NVTX ON)
endif()

if(QUDA_POSIX_THREADS)
  add_definitions(-DPTHREADS)
endif()

if(QUDA_DIRAC_WILSON)
  add_definitions(-DGPU_WILSON_DIRAC)
endif(QUDA_DIRAC_WILSON)

if(QUDA_DIRAC_DOMAIN_WALL)
  add_definitions(-DGPU_DOMAIN_WALL_DIRAC)
endif(QUDA_DIRAC_DOMAIN_WALL)

if (QUDA_DIRAC_STAGGERED)
  add_definitions(-DGPU_STAGGERED_DIRAC)
endif(QUDA_DIRAC_STAGGERED)

if(QUDA_DIRAC_CLOVER)
  add_definitions(-DGPU_CLOVER_DIRAC -DGPU_WILSON_DIRAC -DGPU_GAUGE_TOOLS)
endif(QUDA_DIRAC_CLOVER)

if(QUDA_DIRAC_TWISTED_MASS)
  add_definitions(-DGPU_TWISTED_MASS_DIRAC)
endif(QUDA_DIRAC_TWISTED_MASS)

if(QUDA_DIRAC_TWISTED_CLOVER)
  add_definitions(-DGPU_TWISTED_CLOVER_DIRAC -DGPU_CLOVER_DIRAC -DGPU_TWISTED_MASS_DIRAC -DGPU_WILSON_DIRAC -DGPU_GAUGE_TOOLS)
endif(QUDA_DIRAC_TWISTED_CLOVER)

if(QUDA_DIRAC_NDEG_TWISTED_MASS)
  add_definitions(-DGPU_NDEG_TWISTED_MASS_DIRAC -DGPU_TWISTED_MASS_DIRAC -DGPU_WILSON_DIRAC)
endif(QUDA_DIRAC_NDEG_TWISTED_MASS)

if(QUDA_LINK_ASQTAD)
  add_definitions(-DGPU_FATLINK -DGPU_GAUGE_TOOLS)
endif(QUDA_LINK_ASQTAD)

if(QUDA_LINK_HISQ)
  add_definitions(-DGPU_FATLINK -DGPU_UNITARIZE -DGPU_GAUGE_TOOLS)
endif(QUDA_LINK_HISQ)

if(QUDA_FORCE_GAUGE)
  add_definitions(-DGPU_GAUGE_FORCE -DGPU_GAUGE_TOOLS)
endif(QUDA_FORCE_GAUGE)

if(QUDA_FORCE_ASQTAD)
  add_definitions(-DGPU_FERMION_FORCE -DGPU_GAUGE_TOOLS)
endif(QUDA_FORCE_ASQTAD)

if(QUDA_FORCE_HISQ)
  add_definitions(-DGPU_HISQ_FORCE -DGPU_STAGGERED_OPROD -DGPU_GAUGE_TOOLS)
endif(QUDA_FORCE_HISQ)

if(QUDA_GAUGE_TOOLS)
  add_definitions(-DGPU_GAUGE_TOOLS)
endif(QUDA_GAUGE_TOOLS)

if(QUDA_GAUGE_ALG)
  add_definitions(-DGPU_GAUGE_ALG)
  add_definitions(-DGPU_GAUGE_TOOLS)
  add_definitions(-DGPU_UNITARIZE)
  LIST(APPEND QUDA_LIBS ${CUDA_cufft_LIBRARY} ${CUDA_curand_LIBRARY})
endif(QUDA_GAUGE_ALG)

if(QUDA_DYNAMIC_CLOVER)
  add_definitions(-DDYNAMIC_CLOVER)
endif(QUDA_DYNAMIC_CLOVER)

if(QUDA_MPI_NVTX)
  LIST(APPEND COMM_OBJS nvtx_pmpi.c)
  set(QUDA_NVTX ON)
endif(QUDA_MPI_NVTX)

if(QUDA_INTERFACE_NVTX)
  add_definitions(-DINTERFACE_NVTX)
  set(QUDA_NVTX ON)
endif(QUDA_INTERFACE_NVTX)

if(QUDA_NVTX)
  FIND_LIBRARY(CUDA_NVTX_LIB nvToolsExt ${CUDA_TOOLKIT_ROOT_DIR}/lib/)
  LIST(APPEND QUDA_LIBS ${CUDA_NVTX_LIB})
endif(QUDA_NVTX)

if(NOT QUDA_BLAS_TEX)
  add_definitions(-DDIRECT_ACCESS_BLAS)
endif(NOT QUDA_BLAS_TEX)

if(NOT QUDA_FERMI_DBLE_TEX)
  add_definitions(-DFERMI_NO_DBLE_TEX)
endif(NOT QUDA_FERMI_DBLE_TEX)

if(GPU_DIRECT)
  add_definitions(-DGPU_DIRECT)
endif(GPU_DIRECT)

if(GPU_COMMS)
  add_definitions(-DGPU_COMMS)
endif(GPU_COMMS)

if(QUDA_INTERFACE_QDP)
  add_definitions(-DBUILD_QDP_INTERFACE)
endif(QUDA_INTERFACE_QDP)

if(QUDA_INTERFACE_MILC)
  add_definitions(-DBUILD_MILC_INTERFACE)
endif(QUDA_INTERFACE_MILC)

if(QUDA_INTERFACE_CPS)
  add_definitions(-DBUILD_CPS_INTERFACE)
endif(QUDA_INTERFACE_CPS)

if(QUDA_INTERFACE_QDPJIT)
add_definitions(-DBUILD_QDPJIT_INTERFACE)
endif(QUDA_INTERFACE_QDPJIT)

if(QUDA_INTERFACE_BQCD)
  add_definitions(-DBUILD_BQCD_INTERFACE)
endif(QUDA_INTERFACE_BQCD)

if(QUDA_INTERFACE_TIFR)
  add_definitions(-DBUILD_TIFR_INTERFACE)
endif(QUDA_INTERFACE_TIFR)

# derive whether we need to build the fortran interface
if(QUDA_INTERFACE_TIFR OR QUDA_INTERFACE_BQCD)
  SET(BUILD_FORTRAN_INTERFACE ON)
  enable_language(Fortran)
endif()

if(DEVICE_PACK)
  add_definitions(-DDEVICE_PACK)
endif(DEVICE_PACK)



if(QUDA_NUMA_NVML)
  add_definitions(-DNUMA_NVML)
  set(NUMA_AFFINITY_OBJS numa_affinity.cpp)
  find_package(NVML REQUIRED)
  include_directories(NVML_INCLUDE_DIR)
endif(QUDA_NUMA_NVML)


if(QUDA_CONTRACT)
  add_definitions(-DGPU_CONTRACT)
endif(QUDA_CONTRACT)


# COMPILER OPTIONS and BUILD types
include_directories(${CMAKE_CURRENT_SOURCE_DIR})
include_directories(SYSTEM ${CUDA_INCLUDE_DIRS})
include_directories(include)
include_directories(lib)


# QUDA_HASH for tunecache
file(STRINGS ${CUDA_TOOLKIT_INCLUDE}/cuda.h  CUDA_VERSIONLONG REGEX "\#define CUDA_VERSION" )
STRING(REPLACE "\#define CUDA_VERSION " ""  CUDA_VERSIONLONG ${CUDA_VERSIONLONG})
STRING(STRIP CUDA_VERSIONLONG ${CUDA_VERSIONLONG} )
set(HASH \"cpu_arch=${CPU_ARCH},gpu_arch=${QUDA_GPU_ARCH},cuda_version=${CUDA_VERSIONLONG}\")
add_definitions(-DQUDA_HASH=${HASH})

string(REGEX MATCH [Dd][Ee][Bb][Uu][Gg] DEBUG_BUILD ${CMAKE_BUILD_TYPE})


# add -debug to GITVERSION if we build with debug options enabled
if(DEBUG_BUILD)
  if(GITVERSION)
    set(GITVERSION ${GITVERSION}-debug)
  else()
    set(GITVERSION debug)
  endif()
endif()

IF(GITVERSION)
  add_definitions(-DGITVERSION="${GITVERSION}")
ENDIF()

# GPU ARCH
STRING(REGEX REPLACE sm_ "" COMP_CAP ${QUDA_GPU_ARCH})
SET(COMP_CAP "${COMP_CAP}0")
add_definitions(-D__COMPUTE_CAPABILITY__=${COMP_CAP})


# NVCC FLAGS independet of build type
set(QUDA_NVCC_FLAGS -std c++11 -arch=${QUDA_GPU_ARCH} -ftz=true -prec-div=false -prec-sqrt=false)

if(QUDA_VERBOSE_BUILD)
  LIST(APPEND QUDA_NVCC_FLAGS --ptxas-options=-v)
endif(QUDA_VERBOSE_BUILD)

# some clang warnings shouds be warning even when turning warnings into errors
if (CMAKE_CXX_COMPILER_ID MATCHES "Clang")
    set(CLANG_NOERROR "-Wno-error=unused-private-field")
# this is a hack to get colored diagnostics back when using Ninja and clang
    if(CMAKE_GENERATOR MATCHES "Ninja")
      set(CLANG_FORCE_COLOR "-fcolor-diagnostics")
    endif()
endif()

## define NVCC flags
set(CUDA_NVCC_FLAGS_DEVEL ${QUDA_NVCC_FLAGS} -Xcompiler -Wno-unknown-pragmas,-Wno-unused-function,-Wno-unused-local-typedef,-Wno-unused-private-field -O3 -lineinfo CACHE STRING
    "Flags used by the CUDA compiler during regular development builds."
    FORCE )
set(CUDA_NVCC_FLAGS_STRICT ${CUDA_NVCC_FLAGS_DEVEL} CACHE STRING
    "Flags used by the CUDA compiler during strict jenkins builds."
    FORCE )
set(CUDA_NVCC_FLAGS_RELEASE ${QUDA_NVCC_FLAGS} -O3 -w CACHE STRING
    "Flags used by the C++ compiler during release builds."
    FORCE )
set(CUDA_NVCC_FLAGS_HOSTDEBUG ${QUDA_NVCC_FLAGS} -g -lineinfo -DHOST_DEBUG CACHE STRING
    "Flags used by the C++ compiler during host-debug builds."
    FORCE )
set(CUDA_NVCC_FLAGS_DEVICEDEBUG ${QUDA_NVCC_FLAGS} -G CACHE STRING
    "Flags used by the C++ compiler during device-debug builds."
    FORCE )
set(CUDA_NVCC_FLAGS_DEBUG ${QUDA_NVCC_FLAGS} -g -DHOST_DEBUG -G CACHE STRING
    "Flags used by the C++ compiler during full (host+device) debug builds."
    FORCE )

#define CXX FLAGS
set(CMAKE_CXX_FLAGS_DEVEL  "${OpenMP_CXX_FLAGS} -O3 -Wall ${CLANG_FORCE_COLOR}" CACHE STRING
"Flags used by the C++ compiler during regular development builds.")
set(CMAKE_CXX_FLAGS_STRICT  "${OpenMP_CXX_FLAGS} -O3 -Wall -Werror ${CLANG_NOERROR}" CACHE STRING
"Flags used by the C++ compiler during rstrict jenkins builds.")
set(CMAKE_CXX_FLAGS_RELEASE "${OpenMP_CXX_FLAGS} -O3 -w" CACHE STRING
    "Flags used by the C++ compiler during release builds.")
set(CMAKE_CXX_FLAGS_HOSTDEBUG "${OpenMP_CXX_FLAGS} -Wall -Wno-unknown-pragmas -g -fno-inline -DHOST_DEBUG ${CLANG_FORCE_COLOR}" CACHE STRING
    "Flags used by the C++ compiler during host-debug builds.")
set(CMAKE_CXX_FLAGS_DEVICEDEBUG "${OpenMP_CXX_FLAGS} -Wall -Wno-unknown-pragmas ${CLANG_FORCE_COLOR}" CACHE STRING
    "Flags used by the C++ compiler during device-debug builds.")
set(CMAKE_CXX_FLAGS_DEBUG "${OpenMP_CXX_FLAGS} -Wall -Wno-unknown-pragmas -g -fno-inline -DHOST_DEBUG ${CLANG_FORCE_COLOR}" CACHE STRING
    "Flags used by the C++ compiler during full (host+device) debug builds.")

#define C FLAGS
set(CMAKE_C_FLAGS_DEVEL "-Wall -O3"  CACHE STRING
    "Flags used by the C compiler during regular development builds.")
set(CMAKE_C_FLAGS_STRICT "-Wall -O3 -Werror -Wno-error=unused-private-field"  CACHE STRING
    "Flags used by the C compiler during strict jenkins builds.")
set(CMAKE_C_FLAGS_RELEASE "-Wall -O3 -w" CACHE STRING
    "Flags used by the C compiler during release builds.")
set(CMAKE_C_FLAGS_HOSTDEBUG "-Wall -Wno-unknown-pragmas -g -fno-inline -DHOST_DEBUG" CACHE STRING
    "Flags used by the C compiler during host-debug builds.")
set(CMAKE_C_FLAGS_DEVICEDEBUG "-Wall" CACHE STRING
"Flags used by the C compiler during device-debug builds.")
set(CMAKE_C_FLAGS_DEBUG "-Wall -g -fno-inline -DHOST_DEBUG" CACHE STRING
    "Flags used by the C compiler during full (host+device) debug builds.")

#define FORTRAN FLAGS
set(CMAKE_F_FLAGS -std=c99 CACHE STRING "Fortran Flags")

# make the compiler flags an advanced option for all user defined build types (cmake defined build types are advanced by default )
mark_as_advanced(CMAKE_CXX_FLAGS_DEVEL)
mark_as_advanced(CMAKE_CXX_FLAGS_STRICT)
mark_as_advanced(CMAKE_CXX_FLAGS_HOSTDEBUG)
mark_as_advanced(CMAKE_CXX_FLAGS_DEVICEDEBUG)

mark_as_advanced(CUDA_NVCC_FLAGS_DEVEL)
mark_as_advanced(CUDA_NVCC_FLAGS_STRICT)
mark_as_advanced(CUDA_NVCC_FLAGS_HOSTDEBUG)
mark_as_advanced(CUDA_NVCC_FLAGS_DEVICEDEBUG)

mark_as_advanced(CMAKE_C_FLAGS_DEVEL)
mark_as_advanced(CMAKE_C_FLAGS_STRICT)
mark_as_advanced(CMAKE_C_FLAGS_HOSTDEBUG)
mark_as_advanced(CMAKE_C_FLAGS_DEVICEDEBUG)

mark_as_advanced(CMAKE_F_FLAGS)

### add tests and quda library
add_subdirectory(lib)
add_subdirectory(tests)
#QKXTM: DMH Add QKXTM directory
if(QUDA_INTERFACE_QKXTM)
  add_subdirectory(qkxtm)
endif(QUDA_INTERFACE_QKXTM)
#QKXTM: DMH
