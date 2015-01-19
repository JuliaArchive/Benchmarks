using Base.Cartesian
using Base.Threading

const sixth = 1.0f0/6.0f0
const error_tol = 0.00001

function stencil3d(u::Array{Float32,3}, k_1::Int64, k_2::Int64, k_3::Int64)
    return (u[k_1-1, k_2,   k_3  ] + u[k_1+1, k_2,   k_3] +
            u[k_1,   k_2-1, k_3  ] + u[k_1,   k_2+1, k_3] +
            u[k_1,   k_2,   k_3-1] + u[k_1,   k_2,   k_3+1]) * sixth
end

function l3d_orig(u1::Array{Float32,3}, u3::Array{Float32,3},
                        nx::Int64, ny::Int64, nz::Int64)
    @nloops 3 k u1 begin
        if @nany 3 d->(k_d == 1 || k_d == size(u1, d))
            @inbounds (@nref 3 u3 k) = (@nref 3 u1 k)
        else
            @inbounds (@nref 3 u3 k) = stencil3d(u1, k_1, k_2, k_3)
        end
    end
end

function l3d_threadfun(u1, u3, nx, ny, nz)
    tid = threadid()
    tnz, rem = divrem(nz-2, nthreads())
    z_start = 2 + ((tid-1) * tnz)
    z_end = z_start + tnz - 1
    if tid <= rem
        z_start = z_start + tid - 1
        z_end = z_end + tid
    else
        z_start = z_start + rem
        z_end = z_end + rem
    end

    for k_3 = z_start:z_end
        for k_2 = 2:ny-1
            @simd for k_1 = 2:nx-1
                @inbounds u3[k_1, k_2, k_3] = stencil3d(u1, k_1, k_2, k_3)
            end
        end
    end
end

function l3d_threadblock(u1, u3, nx, ny, nz)
    @threads all begin
	tid = threadid()
	tnz, rem = divrem(nz-2, nthreads())
	z_start = 2 + ((tid-1) * tnz)
	z_end = z_start + tnz - 1
	if tid <= rem
	    z_start = z_start + tid - 1
	    z_end = z_end + tid
	else
	    z_start = z_start + rem
	    z_end = z_end + rem
	end

	for k_3 = z_start:z_end
	    for k_2 = 2:ny-1
		@simd for k_1 = 2:nx-1
		    @inbounds u3[k_1, k_2, k_3] = stencil3d(u1, k_1, k_2, k_3)
		end
	    end
	end
    end
end

function l3d_threadfor(u1, u3, nx, ny, nz)
    @threads all for k_3=2:nz-1
        for k_2 = 2:ny-1
            @simd for k_1 = 2:nx-1
                @inbounds u3[k_1, k_2, k_3] = stencil3d(u1, k_1, k_2, k_3)
            end
        end
    end
end

precompile(l3d_threadfun, (Array{Float32,3}, Array{Float32,3}, Int64, Int64, Int64))
precompile(l3d_threadblock, (Array{Float32,3}, Array{Float32,3}, Int64, Int64, Int64))
precompile(l3d_threadfor, (Array{Float32,3}, Array{Float32,3}, Int64, Int64, Int64))

function laplace3d(nx=258, ny=258, nz=258; iters=100, verify=false)
    u1 = Array(Float32, nx, ny, nz)
    u3 = Array(Float32, nx, ny, nz)
    @nloops 3 k u1 begin
        if @nany 3 d->(k_d == 1 || k_d == size(u1, d))
            (@nref 3 u3 k) = (@nref 3 u1 k) = 1.0
        else
            (@nref 3 u1 k) = 0.0
        end
    end
    @time for n in 1:iters
        # @threads all l3d_threadfun(u1, u3, nx, ny, nz)
	# l3d_threadblock(u1, u3, nx, ny, nz)
        # l3d_threadfor(u1, u3, nx, ny, nz)
        ccall(:jl_threading_run, Void, (Any, Any), l3d_threadfun, (u1, u3, nx, ny, nz))
        foo = u1
        u1 = u3
        u3 = foo
    end
    if verify
        u1_orig = Array(Float32, nx, ny, nz)
        u3_orig = Array(Float32, nx, ny, nz)
        @nloops 3 k u1_orig begin
            if @nany 3 d->(k_d == 1 || k_d == size(u1_orig, d))
                (@nref 3 u3_orig k) = (@nref 3 u1_orig k) = 1.0
            else
                (@nref 3 u1_orig k) = 0.0
            end
        end
        @time for n in 1:iters
            l3d_orig(u1_orig, u3_orig, nx, ny, nz)
            foo = u1_orig
            u1_orig = u3_orig
            u3_orig = foo
        end
        @nloops 3 k u1 begin
            if abs((@nref 3 u1 k) - (@nref 3 u1_orig k)) > error_tol
                error(@sprintf("Verify error: %f - %f [%d, %d, %d]\n",
                      (@nref 3 u1 k), (@nref 3 u1_orig k), k_1, k_2, k_3))
            end
        end
        println("verification succeeded")
    end
end

gc()

laplace3d(verify=true)
#laplace3d(iters=1000, verify=false)

