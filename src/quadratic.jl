type QuadraticDegree <: Degree{2} end
type Quadratic{BC<:BoundaryCondition,GR<:GridRepresentation} <: InterpolationType{QuadraticDegree,BC,GR} end

Quadratic{BC<:BoundaryCondition,GR<:GridRepresentation}(::BC, ::GR) = Quadratic{BC,GR}()

function bc_gen(q::Quadratic, N)
    quote
        pad = padding($q)
        @nexprs $N d->(ix_d = clamp(@compat(round(Integer, x_d)), 1, size(itp,d)) + pad)
    end
end

function bc_gen(::Quadratic{Flat,OnGrid}, N)
    quote
        # After extrapolation has been handled, 1 <= x_d <= size(itp,d)
        # The index is simply the closest integer.
        pad = padding($q)
        @nexprs $N d->(ix_d = @compat round(Integer, x_d)) + pad
        # end
    end
end

function bc_gen(::Quadratic{Flat,OnCell}, N)
    quote
        # After extrapolation has been handled, 0.5 <= x_d <= size(itp,d)+.5
        @nexprs $N d->begin
            # The index is the closest integer...
            ix_d = iround(x_d)

            #...except in the case where x_d is actually at the upper edge;
            # since size(itp,d)+.5 is rounded toward size(itp,d)+1,
            # it needs special treatment*.
            if x_d == size(itp,d)+.5
                ix_d -= 1
            end
        end
    end
end
function bc_gen(::Quadratic{LinearBC,OnCell}, N)
    quote
         @nexprs $N d->begin
            if x_d < 1
                # extrapolate towards -∞
                fx_d = x_d - convert(typeof(x_d), 1)
                k = itp[2] - itp[1]

                return itp[1] + k * fx_d
            end
            if x_d > size(itp, d)
                # extrapolate towards ∞
                s_d = size(itp, d)
                fx_d = x_d - convert(typeof(x_d), s_d)
                k = itp[s_d] - itp[s_d - 1]

                return itp[s_d] + k * fx_d
            end

            ix_d = iround(x_d)
         end
    end
end

function indices(::Quadratic{Flat,OnGrid}, N)
    quote
        @nexprs $N d->begin
            ixp_d = ix_d + 1
            ixm_d = ix_d - 1

            fx_d = x_d - convert(typeof(x_d), ix_d)

            if ix_d == size(itp,d)
                ixp_d = ixm_d
            end
            if ix_d == 1
                ixm_d = ixp_d
            end
        end
    end
end
function indices(::Quadratic{Flat,OnCell}, N)
    quote
        @nexprs $N d->begin
            ixp_d = ix_d + 1
            ixm_d = ix_d - 1

            fx_d = x_d - convert(typeof(x_d), ix_d)

            if ix_d == size(itp,d)
                ixp_d = ix_d
            end
            if ix_d == 1
                ixm_d = ix_d
            end
        end
    end
end
function indices(::Quadratic{LinearBC,OnCell}, N)
    quote
        @nexprs $N d->begin
            ixp_d = ix_d + 1
            ixm_d = ix_d - 1

            fx_d = x_d - convert(typeof(x_d), ix_d)
        end
    end
end

function coefficients(::Quadratic, N)
    quote
        @nexprs $N d->begin
            cm_d = (fx_d-.5)^2 / 2
            c_d = .75 - fx_d^2
            cp_d = (fx_d+.5)^2 / 2
        end
    end
end

# This assumes integral values ixm_d, ix_d, and ixp_d (typically ixm_d = ix_d-1, ixp_d = ix_d+1, except at boundaries),
# coefficients cm_d, c_d, and cp_d, and an array itp.coefs
function index_gen(degree::QuadraticDegree, N::Integer, offsets...)
    if length(offsets) < N
        d = length(offsets)+1
        symm, sym, symp =  symbol(string("cm_",d)), symbol(string("c_",d)), symbol(string("cp_",d))
        return :($symm * $(index_gen(degree, N, offsets...,-1)) + $sym * $(index_gen(degree, N, offsets..., 0)) +
                 $symp * $(index_gen(degree, N, offsets..., 1)))
    else
        indices = [offsetsym(offsets[d], d) for d = 1:N]
        return :(itp.coefs[$(indices...)])
    end
end

function unmodified_system_matrix{T}(::Type{T}, n::Int, ::Quadratic)
    du = fill(convert(T,1/8), n-1)
    d = fill(convert(T,3/4),n)
    dl = copy(du)
    (dl,d,du)
end

function prefiltering_system_matrix{T}(::Type{T}, n::Int, q::Quadratic{ExtendInner})
    dl,d,du = unmodified_system_matrix(T,n,q)
    d[1] = d[end] = 9/8
    du[1] = dl[end] = -1/4
    MT = lufact!(Tridiagonal(dl, d, du))
    U = zeros(T,n,2)
    V = zeros(T,2,n)
    C = zeros(T,2,2)

    C[1,1] = C[2,2] = 1/8
    U[1,1] = U[n,2] = 1.
    V[1,3] = V[2,n-2] = 1.

    Woodbury(MT, U, C, V)
end

function prefiltering_system_matrix{T}(::Type{T}, n::Int, q::Quadratic{Flat,OnCell})
    dl,d,du = unmodified_system_matrix(T,n,q)
    d[1] += 1/8
    d[end] += 1/8
    lufact!(Tridiagonal(dl, d, du))
end

function prefiltering_system_matrix{T}(::Type{T}, n::Int, q::Quadratic{Flat,OnGrid})
    dl,d,du = unmodified_system_matrix(T,n,q)
    du[1] += 1/8
    dl[end] += 1/8
    lufact!(Tridiagonal(dl, d, du))
end

function prefiltering_system_matrix{T}(::Type{T}, n::Int, q::Quadratic{LinearBC,OnCell})
    dl,d,du = unmodified_system_matrix(T,n,q)

    d[1] = d[end] = 1
    du[1] = dl[end] = 0
    lufact!(Tridiagonal(dl, d, du))
end
