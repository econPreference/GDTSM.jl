"""
loglik_mea(yields, τₙ; κQ, kQ_infty, ϕ, σ²FF, Σₒ)
* This function generate a log likelihood of the measurement equation.
* Inputs: yields should exclude their initial conditions. τₙ is maturities in "yields".
* Output: the measurement equation part of the log likelihood
"""
function loglik_mea(yields, τₙ; κQ, kQ_infty, ϕ, σ²FF, Σₒ)

    PCs, OCs, Wₚ, Wₒ = PCA(yields, 0)
    bτ_ = bτ(τₙ[end]; κQ)
    Bₓ_ = Bₓ(bτ_, τₙ)
    T1X_ = T1X(Bₓ_, Wₚ)
    Bₚ_ = Bₚ(Bₓ_, T1X_, Wₒ)

    ΩPP = ϕ_σ²FF_2_ΩPP(; ϕ, σ²FF)
    aτ_ = aτ(τₙ[end], bτ_, τₙ, Wₚ; kQ_infty, ΩPP)
    Aₓ_ = Aₓ(aτ_, τₙ)
    T0P_ = T0P(T1X_, Aₓ_, Wₚ)
    Aₚ_ = Aₚ(Aₓ_, Bₓ_, T0P_, Wₒ)

    T = size(OCs, 1)
    dist_mea = MvNormal(diagm(Σₒ))
    residuals = (OCs' - (Aₚ_ .+ Bₚ_ * PCs'))'

    logpdf_ = 0
    for t = 1:T
        logpdf_ += logpdf(dist_mea, residuals[t, :])
    end

    return logpdf_
end

"""
loglik_tran(PCs, macros; ϕ, σ²FF)
* It calculate log likelihood of the transition equation. 
* Input: All data should contains initial conditions.
* Output: log likelihood of the transition equation.
"""
function loglik_tran(PCs, macros; ϕ, σ²FF)

    dP = length(σ²FF)
    p = ((size(ϕ, 2) - 1) / dP) - 1

    yϕ, Xϕ = yϕ_Xϕ(PCs, macros, p)

    T = size(yϕ, 1)
    logpdf_ = Vector{Float64}(undef, dP)
    for i in 1:dP
        logpdf_[i] = logpdf(MvNormal(Xϕ * (ϕ[i, :]), σ²FF[i] * I(T)), yϕ[:, i])
    end

    return sum(logpdf_)
end

"""
yϕ_Xϕ(PCs, macros, p)
* This function generate the dependent variable and the corresponding regressors in the orthogonal transition equation.
* Input: PCs and macros data should contain initial conditions. p is the transition equation lag.
* Output(4): yϕ, Xϕ = [ones(T - p) Xϕ_lag Xϕ_contemporaneous], [ones(T - p) Xϕ_lag], Xϕ_contemporaneous
    - yϕ and Xϕ is a full matrix. For i'th equation, the dependent variable is yϕ[:,i] and the regressor is Xϕ. 
    - Xϕ is same to all orthogonalized transtion equations. The orthogonalized equations are different in terms of contemporaneous regressors. Therefore, the corresponding regressors in Xϕ should be excluded. The form of parameter ϕ do that task by setting the coefficients of the excluded regressors to zeros.
    - For last dP by dP block in ϕ, the diagonals and the upper diagonal elements should be zero. 
"""
function yϕ_Xϕ(PCs, macros, p)

    data = [PCs macros]
    T = size(data, 1) # length including initial conditions
    dP = size(data, 2)

    yϕ = data[(p+1):T, :]

    Xϕ_lag = Matrix{Float64}(undef, T - p, dP * p)
    Xϕ_contem = Matrix{Float64}(undef, T - p, dP)
    for t in (p+1):T
        Xϕ_lag[t-p, :] = vec(data[(t-1):-1:(t-p), :]')'
        Xϕ_contem[t-p, :] = -data[t, :]
    end
    Xϕ = [ones(T - p) Xϕ_lag Xϕ_contem]

    return yϕ, Xϕ, [ones(T - p) Xϕ_lag], Xϕ_contem
end

"""
LDLt(X)
* This function generate a matrix decomposition, called LDLt. X = L*D*L', where L is a lower triangular matrix and D is a diagonal. How to conduct it can be found at [Wikipedia](https://en.wikipedia.org/wiki/Cholesky_decomposition#LDL_decomposition).
* Input: Decomposed Object, X
* Output(2): L, D
    - Decomposed result is X = L*D*L'
"""
function LDLt(X)
    C = cholesky(X).L
    S = Diagonal(diagm(diag(C)))
    L = C / S
    D = S^2

    return L, D
end

"""
ϕ_σ²FF_2_ΩPP(; ϕ, σ²FF)
* It construct ΩPP from statistical parameters.
* Output: ΩPP
"""
function ϕ_σ²FF_2_ΩPP(; ϕ, σ²FF)

    dQ = dimQ()
    ~, C = ϕ_2_ϕ₀_C(; ϕ)

    CQQ = C[1:dQ, 1:dQ]
    return (CQQ \ diagm(σ²FF[1:dQ])) / CQQ'

end

"""
ϕ_2_ϕ₀_C(; ϕ)
* It divide ϕ into the lagged regressor part and the contemporaneous regerssor part.
* Output(3): ϕ0, C = C0 + I, C0
    * ϕ0: coefficients for the lagged regressors
    * C: coefficients for the dependent variables when all contemporaneous variables are in the LHS of the orthogonalized equations. Therefore, the diagonals of C is ones. 
        - Note that since the contemporaneous variables get negative signs when they are at the RHS, the signs of C do not change whether they are at the RHS or LHS. 
"""
function ϕ_2_ϕ₀_C(; ϕ)

    dP = size(ϕ, 1)
    ϕ0 = ϕ[:, 1:(end-dP)]
    C0 = ϕ[:, (end-dP+1):end]
    C = C0 + I(dP)

    return ϕ0, C, C0
end

"""
isstationary(GₚFF)
* It checks whether a reduced VAR matrix has unit roots. If there is at least one unit root, return is false.
* GₚFF should not include intercepts. Also, GₚFF is dP by dP*p matrix that the coefficient at lag 1 comes first, and the lag p slope matrix comes last. 
* Output: boolean
"""
function isstationary(GₚFF)
    dP = size(GₚFF, 1)
    p = Int(size(GₚFF, 2) / dP)

    G = [GₚFF
        I(dP * (p - 1)) zeros(dP * (p - 1), dP)]

    return maximum(abs.(eigen(G).values)) < 1
end

""" 
stationary_saved_θ(saved_θ)
* It filters out posterior samples that implies an unit root VAR system. Only stationary posterior samples remain.
* Output(2): stationary samples, acceptance rate(%)
    - The second output indicates how many posterior samples remain.
    - "κQ", "kQ_infty", "ϕ", "σ²FF" , "ηψ", "ψ", "ψ0","Σₒ", "γ" ∈ Output[i]
"""
function stationary_saved_θ(saved_θ)

    iteration = length(saved_θ)
    stationary_saved_θ = []
    @showprogress 1 "Filtering..." for iter in 1:iteration

        κQ = saved_θ[iter]["κQ"]
        kQ_infty = saved_θ[iter]["kQ_infty"]
        ϕ = saved_θ[iter]["ϕ"]
        σ²FF = saved_θ[iter]["σ²FF"]
        ηψ = saved_θ[iter]["ηψ"]
        ψ = saved_θ[iter]["ψ"]
        ψ0 = saved_θ[iter]["ψ0"]
        Σₒ = saved_θ[iter]["Σₒ"]
        γ = saved_θ[iter]["γ"]

        ϕ0, C = ϕ_2_ϕ₀_C(; ϕ)
        ϕ0 = C \ ϕ0
        GₚFF = ϕ0[:, 2:end]

        if isstationary(GₚFF)
            push!(stationary_saved_θ,
                Dict(
                    "κQ" => κQ,
                    "kQ_infty" => kQ_infty,
                    "ϕ" => ϕ,
                    "σ²FF" => σ²FF,
                    "ηψ" => ηψ,
                    "ψ" => ψ,
                    "ψ0" => ψ0,
                    "Σₒ" => Σₒ,
                    "γ" => γ
                ))
        end
    end

    return stationary_saved_θ, 100length(stationary_saved_θ) / iteration
end