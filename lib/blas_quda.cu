#include <stdlib.h>
#include <stdio.h>
#include <cstring> // needed for memset



#include <tune_quda.h>
#include <typeinfo>

#include <quda_internal.h>
#include <float_vector.h>
#include <blas_quda.h>
#include <color_spinor_field.h>
#include <color_spinor_field_order.h>
#include <face_quda.h> // this is where the MPI / QMP depdendent code is

#define checkSpinor(a, b)						\
  {									\
    if (a.Precision() != b.Precision())					\
      errorQuda("precisions do not match: %d %d", a.Precision(), b.Precision()); \
    if (a.Length() != b.Length())					\
      errorQuda("lengths do not match: %lu %lu", a.Length(), b.Length()); \
    if (a.Stride() != b.Stride())					\
      errorQuda("strides do not match: %d %d", a.Stride(), b.Stride());	\
  }

#define checkLength(a, b)						\
  {									\
    if (a.Length() != b.Length())					\
      errorQuda("lengths do not match: %lu %lu", a.Length(), b.Length()); \
    if (a.Stride() != b.Stride())					\
      errorQuda("strides do not match: %d %d", a.Stride(), b.Stride());	\
  }

namespace quda {

  namespace blas {

#define BLAS_SPINOR // do not include ghost functions in Spinor class to reduce parameter space overhead
#include <texture.h>

    unsigned long long flops;
    unsigned long long bytes;

    void zero(ColorSpinorField &a) {
      if (typeid(a) == typeid(cudaColorSpinorField)) {
	static_cast<cudaColorSpinorField&>(a).zero();
      } else {
	static_cast<cpuColorSpinorField&>(a).zero();
      }
    }

    static cudaStream_t *blasStream;

    static struct {
      const char *vol_str;
      const char *aux_str;
      char aux_tmp[TuneKey::aux_n];
    } blasStrings;

    void initReduce();
    void endReduce();

    void init()
    {
      blasStream = &streams[Nstream-1];
      initReduce();
    }

    void end(void)
    {
      endReduce();
    }

    cudaStream_t* getStream() { return blasStream; }

#include <blas_core.cuh>

#include <blas_core.h>
#include <blas_mixed_core.h>
#include <multi_blas_core.cuh>
#include <multi_blas_core.h>


    template <typename Float2, typename FloatN>
    struct BlasFunctor {

      //! pre-computation routine before the main loop
      virtual __device__ __host__ void init() { ; }

      //! where the reduction is usually computed and any auxiliary operations
      virtual __device__ __host__ void operator()(FloatN &x, FloatN &y, FloatN &z, FloatN &w) = 0;
    };

    template <int NXZ, typename Float2, typename FloatN>
    struct MultiBlasFunctor {

      //! pre-computation routine before the main loop
      virtual __device__ __host__ void init() { ; }

      //! where the reduction is usually computed and any auxiliary operations
      virtual __device__ __host__ void operator()(FloatN &x, FloatN &y, FloatN &z, FloatN &w, const int i, const int j) = 0;
    };

    /**
       Functor to perform the operation y = a*x + b*y
    */
    template <typename Float2, typename FloatN>
    struct axpby_ : public BlasFunctor<Float2,FloatN> {
      const Float2 a;
      const Float2 b;
      axpby_(const Float2 &a, const Float2 &b, const Float2 &c) : a(a), b(b) { ; }
      __device__ __host__ void operator()(FloatN &x, FloatN &y, FloatN &z, FloatN &w)
      { y = a.x*x + b.x*y; }
      static int streams() { return 3; } //! total number of input and output streams
      static int flops() { return 3; } //! flops per element
    };

    void axpby(const double &a, ColorSpinorField &x, const double &b, ColorSpinorField &y) {
      if (x.Precision() != y.Precision()) {
	// call hacked mixed precision kernel
	mixed::blasCuda<axpby_,0,1,0,0>(make_double2(a,0.0), make_double2(b,0.0), make_double2(0.0,0.0),
				       x, y, x, x);
      } else {
	blasCuda<axpby_,0,1,0,0>(make_double2(a, 0.0), make_double2(b, 0.0), make_double2(0.0, 0.0),
				 x, y, x, x);
      }
    }

    /**
       Functor to perform the operation y += x
    */
    template <typename Float2, typename FloatN>
    struct xpy_ : public BlasFunctor<Float2,FloatN> {
      xpy_(const Float2 &a, const Float2 &b, const Float2 &c) { ; }
      __device__ __host__ void operator()(FloatN &x, FloatN &y, FloatN &z, FloatN &w) { y += x ; }
      static int streams() { return 3; } //! total number of input and output streams
      static int flops() { return 1; } //! flops per element
    };

    void xpy(ColorSpinorField &x, ColorSpinorField &y) {
      blasCuda<xpy_,0,1,0,0>(make_double2(1.0, 0.0), make_double2(1.0, 0.0),
			     make_double2(0.0, 0.0), x, y, x, x);
    }

    /**
       Functor to perform the operation y += a*x
    */
    template <typename Float2, typename FloatN>
    struct axpy_ : public BlasFunctor<Float2,FloatN> {
      const Float2 a;
      axpy_(const Float2 &a, const Float2 &b, const Float2 &c) : a(a) { ; }
      __device__ __host__ void operator()(FloatN &x, FloatN &y, FloatN &z, FloatN &w) { y = a.x*x + y; }
      static int streams() { return 3; } //! total number of input and output streams
      static int flops() { return 2; } //! flops per element
    };

    void axpy(const double &a, ColorSpinorField &x, ColorSpinorField &y) {
      if (x.Precision() != y.Precision()) {
	// call hacked mixed precision kernel
	mixed::blasCuda<axpy_,0,1,0,0>(make_double2(a,0.0), make_double2(1.0,0.0), make_double2(0.0,0.0),
				       x, y, x, x);
      } else {
	blasCuda<axpy_,0,1,0,0>(make_double2(a, 0.0), make_double2(1.0, 0.0), make_double2(0.0, 0.0),
			       x, y, x, x);
      }
    }

    /**
       Functor to perform the operation y = x + a*y
    */
    template <typename Float2, typename FloatN>
    struct xpay_ : public BlasFunctor<Float2,FloatN> {
      const Float2 a;
      xpay_(const Float2 &a, const Float2 &b, const Float2 &c) : a(a) { ; }
      __device__ __host__ void operator()(FloatN &x, FloatN &y, FloatN &z, FloatN &w) { y = x + a.x*y; }
      static int streams() { return 3; } //! total number of input and output streams
      static int flops() { return 2; } //! flops per element
    };

    void xpay(ColorSpinorField &x, const double &a, ColorSpinorField &y) {
      blasCuda<xpay_,0,1,0,0>(make_double2(a,0.0), make_double2(0.0, 0.0), make_double2(0.0, 0.0),
			     x, y, x, x);
    }

    /**
       Functor to perform the operation y -= x;
    */
    template <typename Float2, typename FloatN>
    struct mxpy_ : public BlasFunctor<Float2,FloatN> {
      mxpy_(const Float2 &a, const Float2 &b, const Float2 &c) { ; }
      __device__ __host__ void operator()(FloatN &x, FloatN &y, FloatN &z, FloatN &w) { y -= x; }
      static int streams() { return 3; } //! total number of input and output streams
      static int flops() { return 1; } //! flops per element
    };

    void mxpy(ColorSpinorField &x, ColorSpinorField &y) {
      blasCuda<mxpy_,0,1,0,0>(make_double2(1.0, 0.0), make_double2(1.0, 0.0),
			     make_double2(0.0, 0.0), x, y, x, x);
    }

    /**
       Functor to perform the operation x *= a
    */
    template <typename Float2, typename FloatN>
    struct ax_ : public BlasFunctor<Float2,FloatN> {
      const Float2 a;
      ax_(const Float2 &a, const Float2 &b, const Float2 &c) : a(a) { ; }
      __device__ __host__ void operator()(FloatN &x, FloatN &y, FloatN &z, FloatN &w) { x *= a.x; }
      static int streams() { return 2; } //! total number of input and output streams
      static int flops() { return 1; } //! flops per element
    };

    void ax(const double &a, ColorSpinorField &x) {
      blasCuda<ax_,1,0,0,0>(make_double2(a, 0.0), make_double2(0.0, 0.0),
			   make_double2(0.0, 0.0), x, x, x, x);
    }

    /**
       Functor to perform the operation y += a * x  (complex-valued)
    */

    __device__ __host__ void _caxpy(const float2 &a, const float4 &x, float4 &y) {
      y.x += a.x*x.x; y.x -= a.y*x.y;
      y.y += a.y*x.x; y.y += a.x*x.y;
      y.z += a.x*x.z; y.z -= a.y*x.w;
      y.w += a.y*x.z; y.w += a.x*x.w;
    }

    __device__ __host__ void _caxpy(const float2 &a, const float2 &x, float2 &y) {
      y.x += a.x*x.x; y.x -= a.y*x.y;
      y.y += a.y*x.x; y.y += a.x*x.y;
    }

    __device__ __host__ void _caxpy(const double2 &a, const double2 &x, double2 &y) {
      y.x += a.x*x.x; y.x -= a.y*x.y;
      y.y += a.y*x.x; y.y += a.x*x.y;
    }

    template <typename Float2, typename FloatN>
    struct caxpy_ : public BlasFunctor<Float2,FloatN> {
      const Float2 a;
      caxpy_(const Float2 &a, const Float2 &b, const Float2 &c) : a(a) { ; }
      __device__ __host__ void operator()(FloatN &x, FloatN &y, FloatN &z, FloatN &w)
      { _caxpy(a, x, y); }
      static int streams() { return 3; } //! total number of input and output streams
      static int flops() { return 4; } //! flops per element
    };

    void caxpy(const Complex &a, ColorSpinorField &x, ColorSpinorField &y) {
      blasCuda<caxpy_,0,1,0,0>(make_double2(real(a),imag(a)), make_double2(0.0, 0.0),
			       make_double2(0.0, 0.0), x, y, x, x);
    }

    template<int NXZ, typename Float2, typename FloatN>
    struct multicaxpy_ : public MultiBlasFunctor<NXZ, Float2, FloatN> {
      const int NYW;
      multicaxpy_(const Complex *a, int NYW) : NYW(NYW) { }
      __device__ __host__ void operator()(FloatN &x, FloatN &y, FloatN &z, FloatN &w, const int i, const int j)
      {
#ifdef __CUDA_ARCH__
	Float2 *a = reinterpret_cast<Float2*>(Amatrix_d); // fetch coefficient matrix from constant memory
	_caxpy(a[MAX_MULTI_BLAS_N*j+i], x, y);
#else
	Float2 *a = reinterpret_cast<Float2*>(Amatrix_h);
	_caxpy(a[NYW*j+i], x, y);
#endif
      }
      int streams() { return 2*NYW + NXZ*NYW; } //! total number of input and output streams
      int flops() { return 4*NXZ*NYW; } //! flops per real element
    };

    void caxpy(const Complex *a, std::vector<ColorSpinorField*> &x, std::vector<ColorSpinorField*> &y) {
      switch (x.size()) {
      case 1:
	multiblasCuda<1,multicaxpy_,0,1,0,0>(a, 0, 0, x, y, x, y);
        break;
      case 2:
	multiblasCuda<2,multicaxpy_,0,1,0,0>(a, 0, 0, x, y, x, y);
        break;
      case 3:
	multiblasCuda<3,multicaxpy_,0,1,0,0>(a, 0, 0, x, y, x, y);
        break;
      case 4:
	multiblasCuda<4,multicaxpy_,0,1,0,0>(a, 0, 0, x, y, x, y);
        break;
      case 5:
	multiblasCuda<5,multicaxpy_,0,1,0,0>(a, 0, 0, x, y, x, y);
        break;
      case 6:
	multiblasCuda<6,multicaxpy_,0,1,0,0>(a, 0, 0, x, y, x, y);
        break;
      case 7:
	multiblasCuda<7,multicaxpy_,0,1,0,0>(a, 0, 0, x, y, x, y);
        break;
      case 8:
	multiblasCuda<8,multicaxpy_,0,1,0,0>(a, 0, 0, x, y, x, y);
        break;
      case 9:
	multiblasCuda<9,multicaxpy_,0,1,0,0>(a, 0, 0, x, y, x, y);
        break;
      case 10:
	multiblasCuda<10,multicaxpy_,0,1,0,0>(a, 0, 0, x, y, x, y);
        break;
      case 11:
	multiblasCuda<11,multicaxpy_,0,1,0,0>(a, 0, 0, x, y, x, y);
        break;
      case 12:
	multiblasCuda<12,multicaxpy_,0,1,0,0>(a, 0, 0, x, y, x, y);
        break;
      case 13:
	multiblasCuda<13,multicaxpy_,0,1,0,0>(a, 0, 0, x, y, x, y);
        break;
      case 14:
	multiblasCuda<14,multicaxpy_,0,1,0,0>(a, 0, 0, x, y, x, y);
        break;
      case 15:
	multiblasCuda<15,multicaxpy_,0,1,0,0>(a, 0, 0, x, y, x, y);
        break;
      case 16:
	multiblasCuda<16,multicaxpy_,0,1,0,0>(a, 0, 0, x, y, x, y);
        break;
      default:
	// split the problem in half and recurse
	const Complex *a0 = &a[0];
	const Complex *a1 = &a[x.size()*y.size()/2];

	std::vector<ColorSpinorField*> x0(x.begin(), x.begin() + x.size()/2);
	std::vector<ColorSpinorField*> x1(x.begin() + x.size()/2, x.end());

	caxpy(a0, x0, y);
	caxpy(a1, x1, y);
      }
    }

    void caxpy(const Complex *a, ColorSpinorField &x, ColorSpinorField &y) { caxpy(a, x.Components(), y.Components()); }

    /**
       Functor to perform the operation y = a*x + b*y  (complex-valued)
    */

    __device__ __host__ void _caxpby(const float2 &a, const float4 &x, const float2 &b, float4 &y)
    { float4 yy;
      yy.x = a.x*x.x; yy.x -= a.y*x.y; yy.x += b.x*y.x; yy.x -= b.y*y.y;
      yy.y = a.y*x.x; yy.y += a.x*x.y; yy.y += b.y*y.x; yy.y += b.x*y.y;
      yy.z = a.x*x.z; yy.z -= a.y*x.w; yy.z += b.x*y.z; yy.z -= b.y*y.w;
      yy.w = a.y*x.z; yy.w += a.x*x.w; yy.w += b.y*y.z; yy.w += b.x*y.w;
      y = yy; }

    __device__ __host__ void _caxpby(const float2 &a, const float2 &x, const float2 &b, float2 &y)
    { float2 yy;
      yy.x = a.x*x.x; yy.x -= a.y*x.y; yy.x += b.x*y.x; yy.x -= b.y*y.y;
      yy.y = a.y*x.x; yy.y += a.x*x.y; yy.y += b.y*y.x; yy.y += b.x*y.y;
      y = yy; }

    __device__ __host__ void _caxpby(const double2 &a, const double2 &x, const double2 &b, double2 &y)
    { double2 yy;
      yy.x = a.x*x.x; yy.x -= a.y*x.y; yy.x += b.x*y.x; yy.x -= b.y*y.y;
      yy.y = a.y*x.x; yy.y += a.x*x.y; yy.y += b.y*y.x; yy.y += b.x*y.y;
      y = yy; }

    template <typename Float2, typename FloatN>
    struct caxpby_ : public BlasFunctor<Float2,FloatN> {
      const Float2 a;
      const Float2 b;
      caxpby_(const Float2 &a, const Float2 &b, const Float2 &c) : a(a), b(b) { ; }
      __device__ __host__ void operator()(FloatN &x, FloatN &y, FloatN &z, FloatN &w)
      { _caxpby(a, x, b, y); }
      static int streams() { return 3; } //! total number of input and output streams
      static int flops() { return 7; } //! flops per element
    };

    void caxpby(const Complex &a, ColorSpinorField &x, const Complex &b, ColorSpinorField &y) {
      blasCuda<caxpby_,0,1,0,0>(make_double2(REAL(a),IMAG(a)), make_double2(REAL(b), IMAG(b)),
			       make_double2(0.0, 0.0), x, y, x, x);
    }

    /**
       Functor to performs the operation z[i] = x[i] + a*y[i] + b*z[i]
    */

    __device__ __host__ void _cxpaypbz(const float4 &x, const float2 &a, const float4 &y, const float2 &b, float4 &z) {
      float4 zz;
      zz.x = x.x + a.x*y.x; zz.x -= a.y*y.y; zz.x += b.x*z.x; zz.x -= b.y*z.y;
      zz.y = x.y + a.y*y.x; zz.y += a.x*y.y; zz.y += b.y*z.x; zz.y += b.x*z.y;
      zz.z = x.z + a.x*y.z; zz.z -= a.y*y.w; zz.z += b.x*z.z; zz.z -= b.y*z.w;
      zz.w = x.w + a.y*y.z; zz.w += a.x*y.w; zz.w += b.y*z.z; zz.w += b.x*z.w;
      z = zz;
    }

    __device__ __host__ void _cxpaypbz(const float2 &x, const float2 &a, const float2 &y, const float2 &b, float2 &z) {
      float2 zz;
      zz.x = x.x + a.x*y.x; zz.x -= a.y*y.y; zz.x += b.x*z.x; zz.x -= b.y*z.y;
      zz.y = x.y + a.y*y.x; zz.y += a.x*y.y; zz.y += b.y*z.x; zz.y += b.x*z.y;
      z = zz;
    }

    __device__ __host__ void _cxpaypbz(const double2 &x, const double2 &a, const double2 &y, const double2 &b, double2 &z) {
      double2 zz;
      zz.x = x.x + a.x*y.x; zz.x -= a.y*y.y; zz.x += b.x*z.x; zz.x -= b.y*z.y;
      zz.y = x.y + a.y*y.x; zz.y += a.x*y.y; zz.y += b.y*z.x; zz.y += b.x*z.y;
      z = zz;
    }

    template <typename Float2, typename FloatN>
    struct cxpaypbz_ : public BlasFunctor<Float2,FloatN> {
      const Float2 a;
      const Float2 b;
      cxpaypbz_(const Float2 &a, const Float2 &b, const Float2 &c) : a(a), b(b) { ; }
      __device__ __host__ void operator()(FloatN &x, FloatN &y, FloatN &z, FloatN &w)
      { _cxpaypbz(x, a, y, b, z); }
      static int streams() { return 4; } //! total number of input and output streams
      static int flops() { return 8; } //! flops per element
    };

    void cxpaypbz(ColorSpinorField &x, const Complex &a, ColorSpinorField &y,
		  const Complex &b, ColorSpinorField &z) {
      blasCuda<cxpaypbz_,0,0,1,0>(make_double2(REAL(a),IMAG(a)), make_double2(REAL(b), IMAG(b)),
				 make_double2(0.0, 0.0), x, y, z, z);
    }

    /**
       Functor performing the operations: y[i] = a*x[i] + y[i]; x[i] = b*z[i] + c*x[i]
    */
    template <typename Float2, typename FloatN>
    struct axpyBzpcx_ : public BlasFunctor<Float2,FloatN> {
      const Float2 a;
      const Float2 b;
      const Float2 c;
      axpyBzpcx_(const Float2 &a, const Float2 &b, const Float2 &c) : a(a), b(b), c(c) { ; }
      __device__ __host__ void operator()(FloatN &x, FloatN &y, FloatN &z, FloatN &w)
      { y += a.x*x; x = b.x*z + c.x*x; }
      static int streams() { return 5; } //! total number of input and output streams
      static int flops() { return 5; } //! flops per element
    };

    void axpyBzpcx(const double &a, ColorSpinorField& x, ColorSpinorField& y, const double &b,
		   ColorSpinorField& z, const double &c) {
      if (x.Precision() != y.Precision()) {
	// call hacked mixed precision kernel
	mixed::blasCuda<axpyBzpcx_,1,1,0,0>(make_double2(a,0.0), make_double2(b,0.0),
					    make_double2(c,0.0),	x, y, z, x);
      } else {
	// swap arguments around
	blasCuda<axpyBzpcx_,1,1,0,0>(make_double2(a,0.0), make_double2(b,0.0),
				     make_double2(c,0.0), x, y, z, x);
      }
    }


    template<int NXZ, typename Float2, typename FloatN>
    struct multi_axpyBzpcx_ : public MultiBlasFunctor<NXZ, Float2, FloatN> {
      const int NYW;
      multi_axpyBzpcx_(const Complex *a, int NYW) : NYW(NYW) { }
      __device__ __host__ void operator()(FloatN &x, FloatN &y, FloatN &z, FloatN &w, const int i, const int j)
      {
#ifdef __CUDA_ARCH__
	// fetch coefficient arrays from constant memory
	Float2 *a = reinterpret_cast<Float2*>(Amatrix_d);
	Float2 *b = reinterpret_cast<Float2*>(Bmatrix_d);
	Float2 *c = reinterpret_cast<Float2*>(Cmatrix_d);
#else
	Float2 *a = reinterpret_cast<Float2*>(Amatrix_h);
	Float2 *b = reinterpret_cast<Float2*>(Bmatrix_h);
	Float2 *c = reinterpret_cast<Float2*>(Cmatrix_h);
#endif
	w += a[i].x * y;
	y = b[i].x * x + c[i].x * y;
      }
      int streams() { return 4*NYW + NXZ; } //! total number of input and output streams
      int flops() { return 5*NXZ*NYW; } //! flops per real element
    };

    void axpyBzpcx(const double *a_, std::vector<ColorSpinorField*> &x_, std::vector<ColorSpinorField*> &y_,
		   const double *b_, ColorSpinorField &z_, const double *c_) {

      // swizzle order since we are writing to x_ and y_, but the
      // multi-blas only allow writing to y and w, and moreover the
      // block width of y and w must match, and x and z must match.
      std::vector<ColorSpinorField*> &y = x_;
      std::vector<ColorSpinorField*> &w = y_;

      // wrap a container around the third solo vector
      std::vector<ColorSpinorField*> x;
      x.push_back(&z_);

      Complex *a = new Complex[y.size()];
      Complex *b = new Complex[y.size()];
      Complex *c = new Complex[y.size()];

      for (unsigned int i=0; i<y.size(); i++) { a[i] = Complex(a_[i]); b[i] = Complex(b_[i]); c[i] = Complex(c_[i]); }

      multiblasCuda<1,multi_axpyBzpcx_,0,1,0,1>(a, b, c, x, y, x, w);

      delete []a;
      delete []b;
      delete []c;
    }


    /**
       Functor performing the operations: y[i] = a*x[i] + y[i]; x[i] = z[i] + b*x[i]
    */
    template <typename Float2, typename FloatN>
    struct axpyZpbx_ : public BlasFunctor<Float2,FloatN> {
      const Float2 a;
      const Float2 b;
      axpyZpbx_(const Float2 &a, const Float2 &b, const Float2 &c) : a(a), b(b) { ; }
      __device__ __host__ void operator()(FloatN &x, FloatN &y, FloatN &z, FloatN &w)
      { y += a.x*x; x = z + b.x*x; }
      static int streams() { return 5; } //! total number of input and output streams
      static int flops() { return 4; } //! flops per element
    };

    void axpyZpbx(const double &a, ColorSpinorField& x, ColorSpinorField& y,
		  ColorSpinorField& z, const double &b) {
      if (x.Precision() != y.Precision()) {
	// call hacked mixed precision kernel
	mixed::blasCuda<axpyZpbx_,1,1,0,0>(make_double2(a,0.0), make_double2(b,0.0), make_double2(0.0,0.0),
					   x, y, z, x);
      } else {
	// swap arguments around
	blasCuda<axpyZpbx_,1,1,0,0>(make_double2(a,0.0), make_double2(b,0.0), make_double2(0.0,0.0),
				    x, y, z, x);
      }
    }

    /**
       Functor performing the operations z[i] = a*x[i] + b*y[i] + z[i] and y[i] -= b*w[i]
    */
    template <typename Float2, typename FloatN>
    struct caxpbypzYmbw_ : public BlasFunctor<Float2,FloatN> {
      const Float2 a;
      const Float2 b;
      caxpbypzYmbw_(const Float2 &a, const Float2 &b, const Float2 &c) : a(a), b(b) { ; }
      __device__ __host__ void operator()(FloatN &x, FloatN &y, FloatN &z, FloatN &w)
      { _caxpy(a, x, z); _caxpy(b, y, z); _caxpy(-b, w, y); }

      static int streams() { return 6; } //! total number of input and output streams
      static int flops() { return 12; } //! flops per element
    };

    void caxpbypzYmbw(const Complex &a, ColorSpinorField &x, const Complex &b,
		      ColorSpinorField &y, ColorSpinorField &z, ColorSpinorField &w) {
      blasCuda<caxpbypzYmbw_,0,1,1,0>(make_double2(REAL(a),IMAG(a)), make_double2(REAL(b), IMAG(b)),
				     make_double2(0.0,0.0), x, y, z, w);
    }

    /**
       Functor performing the operation y[i] += a*b*x[i], x[i] *= a
    */
    template <typename Float2, typename FloatN>
    struct cabxpyAx_ : public BlasFunctor<Float2,FloatN> {
      const Float2 a;
      const Float2 b;
      cabxpyAx_(const Float2 &a, const Float2 &b, const Float2 &c) : a(a), b(b) { ; }
      __device__ __host__ void operator()(FloatN &x, FloatN &y, FloatN &z, FloatN &w)
      { x *= a.x; _caxpy(b, x, y); }
      static int streams() { return 4; } //! total number of input and output streams
      static int flops() { return 5; } //! flops per element
    };

    void cabxpyAx(const double &a, const Complex &b,
		  ColorSpinorField &x, ColorSpinorField &y) {
      // swap arguments around
      blasCuda<cabxpyAx_,1,1,0,0>(make_double2(a,0.0), make_double2(REAL(b),IMAG(b)),
				  make_double2(0.0,0.0), x, y, x, x);
    }

    /**
       Functor performing the operation z[i] = a*x[i] + b*y[i] + z[i]
    */
    template <typename Float2, typename FloatN>
    struct caxpbypz_ : public BlasFunctor<Float2,FloatN> {
      const Float2 a;
      const Float2 b;
      caxpbypz_(const Float2 &a, const Float2 &b, const Float2 &c) : a(a), b(b) { ; }
      __device__ __host__ void operator()(FloatN &x, FloatN &y, FloatN &z, FloatN &w)
      { _caxpy(a, x, z); _caxpy(b, y, z); }
      static int streams() { return 4; } //! total number of input and output streams
      static int flops() { return 8; } //! flops per element
    };

    void caxpbypz(const Complex &a, ColorSpinorField &x, const Complex &b,
		  ColorSpinorField &y, ColorSpinorField &z) {
      blasCuda<caxpbypz_,0,0,1,0>(make_double2(REAL(a),IMAG(a)), make_double2(REAL(b),IMAG(b)),
				  make_double2(0.0,0.0), x, y, z, z);
    }

    /**
       Functor Performing the operation w[i] = a*x[i] + b*y[i] + c*z[i] + w[i]
    */
    template <typename Float2, typename FloatN>
    struct caxpbypczpw_ : public BlasFunctor<Float2,FloatN> {
      const Float2 a;
      const Float2 b;
      const Float2 c;
      caxpbypczpw_(const Float2 &a, const Float2 &b, const Float2 &c) : a(a), b(b), c(c) { ; }
      __device__ __host__ void operator()(FloatN &x, FloatN &y, FloatN &z, FloatN &w)
      { _caxpy(a, x, w); _caxpy(b, y, w); _caxpy(c, z, w); }

      static int streams() { return 4; } //! total number of input and output streams
      static int flops() { return 12; } //! flops per element
    };

    void caxpbypczpw(const Complex &a, ColorSpinorField &x, const Complex &b,
		     ColorSpinorField &y, const Complex &c, ColorSpinorField &z,
		     ColorSpinorField &w) {
      blasCuda<caxpbypczpw_,0,0,0,1>(make_double2(REAL(a),IMAG(a)), make_double2(REAL(b),IMAG(b)),
				     make_double2(REAL(c),IMAG(c)), x, y, z, w);
    }

    /**
       double caxpyXmaz(c a, V x, V y, V z){}

       First performs the operation y[i] += a*x[i]
       Second performs the operator x[i] -= a*z[i]
    */
    template <typename Float2, typename FloatN>
    struct caxpyxmaz_ : public BlasFunctor<Float2,FloatN> {
      Float2 a;
      caxpyxmaz_(const Float2 &a, const Float2 &b, const Float2 &c) : a(a) { ; }
      __device__ __host__ void operator()(FloatN &x, FloatN &y, FloatN &z, FloatN &w)
      { _caxpy(a, x, y); _caxpy(-a, z, x); }
      static int streams() { return 5; } //! total number of input and output streams
      static int flops() { return 8; } //! flops per element
    };

    void caxpyXmaz(const Complex &a, ColorSpinorField &x,
		   ColorSpinorField &y, ColorSpinorField &z) {
      blasCuda<caxpyxmaz_,1,1,0,0>(make_double2(REAL(a), IMAG(a)), make_double2(0.0, 0.0),
				   make_double2(0.0, 0.0), x, y, z, x);
    }

    /**
       double caxpyXmazMR(c a, V x, V y, V z){}

       First performs the operation y[i] += a*x[i]
       Second performs the operator x[i] -= a*z[i]
    */
    template <typename Float2, typename FloatN>
    struct caxpyxmazMR_ : public BlasFunctor<Float2,FloatN> {
      Float2 a;
      double3 *Ar3;
      caxpyxmazMR_(const Float2 &a, const Float2 &b, const Float2 &c)
	: a(a), Ar3(static_cast<double3*>(blas::getDeviceReduceBuffer())) { ; }

      inline __device__ __host__ void init() {
#ifdef __CUDA_ARCH__
	typedef decltype(a.x) real;
	double3 result = __ldg(Ar3);
	a.y = a.x * (real)(result.y) * ((real)1.0 / (real)result.z);
	a.x = a.x * (real)(result.x) * ((real)1.0 / (real)result.z);
#endif
      }

      __device__ __host__ void operator()(FloatN &x, FloatN &y, FloatN &z, FloatN &w)
      { _caxpy(a, x, y); _caxpy(-a, z, x); }

      static int streams() { return 5; } //! total number of input and output streams
      static int flops() { return 8; } //! flops per element
    };

    void caxpyXmazMR(const Complex &a, ColorSpinorField &x,
		     ColorSpinorField &y, ColorSpinorField &z) {
      if (!commAsyncReduction())
	errorQuda("This kernel requires asynchronous reductions to be set");
      if (x.Location() == QUDA_CPU_FIELD_LOCATION)
	errorQuda("This kernel cannot be run on CPU fields");

      blasCuda<caxpyxmazMR_,1,1,0,0>(make_double2(REAL(a), IMAG(a)), make_double2(0.0, 0.0),
				     make_double2(0.0, 0.0), x, y, z, x);
    }

    /**
       double tripleCGUpdate(d a, d b, V x, V y, V z, V w){}

       First performs the operation y[i] = y[i] + a*w[i]
       Second performs the operation z[i] = z[i] - a*x[i]
       Third performs the operation w[i] = z[i] + b*w[i]
    */
    template <typename Float2, typename FloatN>
    struct tripleCGUpdate_ : public BlasFunctor<Float2,FloatN> {
      Float2 a, b;
      tripleCGUpdate_(const Float2 &a, const Float2 &b, const Float2 &c) : a(a), b(b) { ; }
      __device__ __host__ void operator()(FloatN &x, FloatN &y, FloatN &z, FloatN &w)
      { y += a.x*w; z -= a.x*x; w = z + b.x*w; }
      static int streams() { return 7; } //! total number of input and output streams
      static int flops() { return 6; } //! flops per element
    };

    void tripleCGUpdate(const double &a, const double &b, ColorSpinorField &x,
			ColorSpinorField &y, ColorSpinorField &z, ColorSpinorField &w) {
      if (x.Precision() != y.Precision()) {
      // call hacked mixed precision kernel
	mixed::blasCuda<tripleCGUpdate_,0,1,1,1>(make_double2(a,0.0), make_double2(b,0.0),
						 make_double2(0.0,0.0), x, y, z, w);
      } else {
	blasCuda<tripleCGUpdate_,0,1,1,1>(make_double2(a, 0.0), make_double2(b, 0.0),
					  make_double2(0.0, 0.0), x, y, z, w);
      }
    }

  } // namespace blas

} // namespace quda
