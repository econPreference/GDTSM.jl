"""
_log_marginal(PCs, macros, ρ; p, ν0, Ω0, q, ψ, ψ0)
* This file derives hyper-parameters for priors. The marginal likelihood for the transition equation is maximized at the selected hyperparameters. 
* Input: Data should contain initial conditions. Keywords are hyperparameters. The hyperparameters are
    * p: the lag of the transition equation
    * ν0(d.f.), Ω0(scale): hyper-parameters of the Inverse-Wishart prior distribution for the error covariance matrix in the transition equation
    * q: the degree of shrinkages of the intercept and the slope coefficient of the transition equation
        * q[1]: shrinkages for the lagged dependent variable
        * q[2]: shrinkages for cross variables
        * q[3]: power of the lag shrinkage
        * q[4]: shrinkages for the intercept
    * ρ only indicates macro variables' persistencies.
*Output: the log marginal likelihood of the VAR system.
"""
function _log_marginal(PCs, macros, ρ; p, ν0, Ω0, q, ψ, ψ0)
    dP = length(Ω0)
    yϕ, Xϕ = yϕ_Xϕ(PCs, macros, p)
    T = size(yϕ, 1)
    prior_ϕ0_ = prior_ϕ0(ρ; ψ0, ψ, q, ν0, Ω0)
    prior_C_ = prior_C(; Ω0)
    prior_ϕ = hcat(prior_ϕ0_, prior_C_)
    m = mean.(prior_ϕ)
    V = var.(prior_ϕ)

    log_marginal = -log(2π)
    log_marginal *= (T * dP) / 2
    for i in 1:dP
        νᵢ = ν(i, dP; ν0)
        Sᵢ = S(i; Ω0)
        Vᵢ = V[i, 1:(end-dP+i-1)]
        Kϕᵢ = Kϕ(i, V, Xϕ, dP)
        Sᵢ_hat = S_hat(i, m, V, yϕ, Xϕ, dP; Ω0)
        det_Kϕᵢ = det(Kϕᵢ)
        if min(det_Kϕᵢ, Sᵢ_hat) < 0 || isinf(det_Kϕᵢ)
            return -Inf
        end

        log_marginalᵢ = sum(log.(Vᵢ))
        log_marginalᵢ += log(det_Kϕᵢ)
        log_marginalᵢ /= -2
        log_marginalᵢ += loggamma(νᵢ + 0.5T)
        log_marginalᵢ += νᵢ * log(Sᵢ)
        log_marginalᵢ -= loggamma(νᵢ)
        log_marginalᵢ -= (νᵢ + 0.5T) * log(Sᵢ_hat)

        log_marginal += log_marginalᵢ
    end

    return log_marginal
end

"""
ν(i, dP; ν0)
"""
function ν(i, dP; ν0)
    return (ν0 + i - dP) / 2
end

"""
S(i; Ω0)
"""
function S(i; Ω0)
    return Ω0[i] / 2
end

"""
Kϕ(i, V, Xϕ, dP)
"""
function Kϕ(i, V, Xϕ, dP)
    Xϕᵢ = Xϕ[:, 1:(end-dP+i-1)]
    Vᵢ = V[i, 1:(end-dP+i-1)]
    return diagm(1 ./ Vᵢ) + Xϕᵢ'Xϕᵢ
end

"""
ϕ_hat(i, m, V, yϕ, Xϕ, dP)
"""
function ϕ_hat(i, m, V, yϕ, Xϕ, dP)
    Kϕᵢ = Kϕ(i, V, Xϕ, dP)
    Xϕᵢ = Xϕ[:, 1:(end-dP+i-1)]
    yϕᵢ = yϕ[:, i]
    mᵢ = m[i, 1:(end-dP+i-1)]
    Vᵢ = V[i, 1:(end-dP+i-1)]

    return Kϕᵢ \ (diagm(1 ./ Vᵢ) * mᵢ + Xϕᵢ'yϕᵢ)
end

"""
S_hat(i, m, V, yϕ, Xϕ, dP; Ω0)
"""
function S_hat(i, m, V, yϕ, Xϕ, dP; Ω0)

    yϕᵢ = yϕ[:, i]
    mᵢ = m[i, 1:(end-dP+i-1)]
    Vᵢ = V[i, 1:(end-dP+i-1)]
    Kϕᵢ = Kϕ(i, V, Xϕ, dP)
    ϕᵢ_hat = ϕ_hat(i, m, V, yϕ, Xϕ, dP)

    Sᵢ_hat = S(i; Ω0)
    Sᵢ_hat += (yϕᵢ'yϕᵢ + mᵢ' * diagm(1 ./ Vᵢ) * mᵢ - ϕᵢ_hat' * Kϕᵢ * ϕᵢ_hat) / 2

    return Sᵢ_hat
end
