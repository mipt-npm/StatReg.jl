include("basis.jl")
include("vector.jl")

using Optim

"""
```julia
GaussErrorMatrixUnfolder(
    omegas::Array{Array{Float64, 2} ,1},
    method::String="EmpiricalBayes",
    alphas::Union{Array{Float64, 1}, Nothing}=nothing,
    )
```
`omegas` -- array of matrices that provide information about basis functions

`method` -- constant selection method, possible options: "EmpiricalBayes" and "User"

`alphas` -- array of constants, in case method="User" should be provided by user

Solve model for dicsrete data.
"""
mutable struct GaussErrorMatrixUnfolder
    omegas::Array{Array{Float64, 2} ,1}
    n::Int64
    method::String
    alphas::Union{Array{Float64}, Nothing}

    function GaussErrorMatrixUnfolder(
        omegas::Array{Array{Float64, 2} ,1},
        method::String="EmpiricalBayes",
        alphas::Union{Array{Float64, 1}, Nothing}=nothing,
        )

        if Base.length(omegas) == 0
            Base.error("Regularization matrix Omega is absent")
        end

        if Base.length(size(omegas[1])) != 2
            Base.error("Matrix Omega must have two dimensions")
        end

        n, m = size(omegas[1])
        if n != m
            Base.error("Matrix Omega must be square")
        end

        for omega in omegas
            if length(size(omega)) != 2
                Base.error("Matrix Omega must have two dimensions")
            end
            n1, m1 = size(omega)
            if m1 != m
                Base.error("All omega matrixes must have equal dimensions")
            end
            if m1 != n1
                Base.error("Matrix Omega must be square")
            end
        end

        if method == "User"
            if alphas == nothing
                Base.error("alphas must be defined for method='User'")
            end
            if Base.length(alphas) != Base.length(omegas)
                Base.error("Omegas and alphas must have equal size")
            end
        end

        return new(omegas, m, method, alphas)
    end
end


"""
```julia
solve(
    unfolder::GaussErrorMatrixUnfolder,
    kernel::Array{Float64, 2},
    data::Array{Float64, 1},
    data_errors::Union{Array{Float64, 1}, Array{Float64, 2}},
    )
```

Returns dictionary with coefficients, errors and optimal constants.
"""
function solve(
    unfolder::GaussErrorMatrixUnfolder,
    kernel::Array{Float64, 2},
    data::Array{Float64, 1},
    data_errors::Union{Array{Float64, 1}, Array{Float64, 2}},
    )

    println("starting solve")
    m, n = size(kernel)
    if n != unfolder.n
        Base.error("Kernel and unfolder must have equal dimentions.")
    end

    if size(data)[1] != m
        Base.error("K and f must be (m,n) and (m,) dimensional.")
    end

    if length(size(data_errors)) == 1
        data_errors = cat(data_errors...; dims=(1,2))
    elseif length(size(data_errors)) != 2
        Base.error("Sigma matrix must be two-dimensional.")
    end

    if size(data_errors)[1] != size(data_errors)[2]
        Base.error("Sigma matrix must be square.")
    end

    if size(data)[1] != size(data_errors)[1]
        Base.error("Sigma matrix and f must have equal dimensions.")
    end
    println("ending solve")
    return solve_correct(unfolder, kernel, data, data_errors)
end

function solve_correct(
    unfolder::GaussErrorMatrixUnfolder,
    kernel::Array{Float64, 2},
    data::Array{Float64, 1},
    data_errors::Array{Float64, 2},
    )

    println("starting solve_correct")
    K = kernel
    Kt = transpose(kernel)
    data_errorsInv = inv(data_errors)
    B = Kt * data_errorsInv * K
    b = Kt * transpose(data_errorsInv) * data

    function optimal_alpha()
        println("starting optimal_alpha")
        function alpha_prob(a::Array{Float64, 1})
            aO = transpose(a)*unfolder.omegas
            BaO = B + aO
#             if det(BaO) == 0
#                 println("det(BaO) = 0")
#             end
            iBaO = inv(BaO)
            dotp = transpose(b) * iBaO * b
            if det(aO) != 0
                detaO = log(abs(det(aO)))
            else
                eigvals_aO = sort(eigvals(aO))
                rank_deficiency = size(aO)[1] - rank(aO)
                detaO = sum(log.(abs.(eigvals_aO[(rank_deficiency+1):end])))
            end
            detBaO = log(abs(det(BaO)))
            return detaO - detBaO + dotp
        end

        a0 = zeros(Float64, Base.length(unfolder.omegas))
        println("starting optimize")

        my_alphas = collect(range(-100, 0.5, length=500))
        alphas = [[exp(my_alpha)] for my_alpha in my_alphas]
        plot(exp.(my_alphas), -alpha_prob.(alphas))

        res = optimize(
            a -> -alpha_prob(exp.(a)), a0,  BFGS(),
            Optim.Options(x_tol=X_TOL_OPTIM, show_trace=true,
            store_trace=true, allow_f_increases=true))

        if !Optim.converged(res)
            # Base.error("Minimization did not succeed")
            println("Minimization did not succeed")
            return [0.05]
        end
        alpha = exp.(Optim.minimizer(res))
        if (alpha[1] - 0.) < 1e-6 || alpha[1] > 1e3
            println("Incorrect alpha")
            alpha = [0.05]
        end
        return alpha
    end

    if unfolder.method == "EmpiricalBayes"
        unfolder.alphas = optimal_alpha()
    end

    BaO = B + transpose(unfolder.alphas)*unfolder.omegas
    iBaO = inv(BaO)
    r = iBaO * b
    println("ending solve_correct")
    return Dict("coeff" => r, "sig" => iBaO, "alphas" => unfolder.alphas)
end


"""
```julia
GaussErrorUnfolder(
    basis::Basis,
    omegas::Array,
    method::String="EmpiricalBayes",
    alphas::Union{Array{Float64, 1}, Nothing}=nothing,
    )
```

`basis` -- basis for reconstruction

`omegas` -- array of matrices that provide information about basis functions

`method` -- constant selection method, possible options: "EmpiricalBayes" and "User"

`alphas` -- array of constants, in case method="User" should be provided by user

"""
mutable struct GaussErrorUnfolder
    basis::Basis
    solver::GaussErrorMatrixUnfolder

    function GaussErrorUnfolder(
        basis::Basis,
        omegas::Array,
        method::String="EmpiricalBayes",
        alphas::Union{Array{Float64, 1}, Nothing}=nothing,
        )

        solver = GaussErrorMatrixUnfolder(omegas, method, alphas)
        return new(basis, solver)
    end
end


"""
```julia
solve(
    gausserrorunfolder::GaussErrorUnfolder,
    kernel::Union{Function, Array{Float64, 2}},
    data::Union{Function, Array{Float64, 1}},
    data_errors::Union{Function, Array{Float64, 1}},
    y::Union{Array{Float64, 1}, Nothing},
    )
```

Returns dictionary with coefficients, errors and optimal constants.
"""
function solve(
    gausserrorunfolder::GaussErrorUnfolder,
    kernel::Union{Function, Array{Float64, 2}},
    data::Union{Function, Array{Float64, 1}},
    data_errors::Union{Function, Array{Float64, 1}},
    y::Union{Array{Float64, 1}, Nothing},
    )

    println("starting solve")
    function check_y()
        if y == nothing
            Base.error("For callable arguments `y` must be defined")
        end
    end

    if !(typeof(kernel) == Array{Float64, 2})
        check_y()
        kernel_array = discretize_kernel(gausserrorunfolder.basis, kernel, y)
    else
        kernel_array = kernel
    end

    if !(typeof(data) == Array{Float64, 1})
        check_y()
        data_array = data.(y)
    else
        data_array = data
    end

    if !(typeof(data_errors) == Array{Float64, 1})
        check_y()
        data_errors_array = data_errors.(y)
    else
        data_errors_array = data_errors
    end
    println("ending solve")
    result = solve(
        gausserrorunfolder.solver,
        kernel_array, data_array, data_errors_array
    )
    return result
end
