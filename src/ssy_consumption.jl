#=

Discreization of the consumption process in Schorfheide, Song and Yaron, where
log consumption growth g is given by

    g = μ + z + σ_c η'

    z' = ρ z + sqrt(1 - ρ^2) σ_z e'

    σ_z = ϕ_z σ_bar exp(h_z)

    σ_c = ϕ_c σ_bar exp(h_c)

    h_z' = ρ_hz h_z + σ_hz u'

    h_c' = ρ_hc h_c + σ_hc w'

Here {e}, {u} and {w} are IID and N(0, 1).  

The discretization method uses iterations of Rouwenhorst.  The indices are

    σ_c[k] for k in 1:K
    σ_z[i] for i in 1:I
    z[i, :] is all z states when σ_z = σ_z[i]  -- z[i, j] is j-th element

The discretized version is a representation of a Markov chain with finitely
many states 

    x = (σ_c, σ_z, z)

and stochastic matrix Q giving transition probabilitites between them.

The set of states x_states is computed as a 3 x M matrix with each column
corresponding to values of (σ_c, σ_z, z)'

Discretize the SSY state process builds the discretized state values for the
    states (σ_c, σ_z, z) and a transition matrix Q such that 

    Q[m, mp] = probability of transition x[m] -> x[mp]

where

    x[m] := (σ_c[k], σ_z[i], z[i,j])
    
The rule for the index is

    m = (k-1) * (I * J) + (i - 1) * J + j

=#

include("consumption.jl")
import QuantEcon: rouwenhorst, MarkovChain


"""
Struct for parameters of SSY model

"""
mutable struct SSYconsumption{T <: Real}  <: ConsumptionProcess
    μ::T 
    ρ::T 
    ϕ_z::T 
    σ_bar::T
    ϕ_c::T
    ρ_hz::T
    σ_hz::T
    ρ_hc::T 
    σ_hc::T 
end


"""
Default values from May 2017 version of Schorfheide, Song and Yaron. 
See p. 28.

"""

function SSYconsumption()
    return SSYconsumption(0.0016,              # μ
               0.987,               # ρ
               0.215,               # ϕ_z
               0.0032,              # σ_bar
               1.0,                 # ϕ_c
               0.992,               # ρ_hz
               sqrt(0.0039),        # σ_hz
               0.991,               # ρ_hc
               sqrt(0.0096))        # σ_hc
end


"""
A struct to store parameters and the discretized version of the consumption
process.

"""
struct SSYconsumptionDiscretized{T <: Real} <: DiscretizedConsumptionProcess
    ssy::SSYconsumption{T}
    K::Int64
    I::Int64
    J::Int64
    σ_c_states::Vector{T}
    σ_z_states::Vector{T}
    z_states::Array{T}
    x_states::Array{T}
    Q::Array{T}
end



"""
A utility function for the multi-index.
"""
split_index(i, M) = div(i - 1, M) + 1, rem(i - 1, M) + 1


function single_to_multi(m, I, J)
    k, temp = split_index(m, I * J)
    i, j = split_index(temp, J)
    return k, i, j
end

multi_to_single(k, i, j, I, J) = (k-1) * (I * J) + (i - 1) * J + j


"""
And here's the actual discretization process.  

"""
function discretize(ssy::SSYconsumption, 
                    K::Integer, 
                    I::Integer, 
                    J::Integer) 

    # Unpack
    ρ, ϕ_z, σ_bar, ϕ_c, ρ_hz, σ_hz, ρ_hc, σ_hc = 
        ssy.ρ, ssy.ϕ_z, ssy.σ_bar, ssy.ϕ_c, ssy.ρ_hz, ssy.σ_hz, ssy.ρ_hc, ssy.σ_hc

    ## Discretize by applying rouwenhorst to h_c and h_z
    hc_mc = rouwenhorst(K, ρ_hc, σ_hc)
    hz_mc = rouwenhorst(I, ρ_hz, σ_hz)

    σ_c_states  = ϕ_c * σ_bar * exp.(collect(hc_mc.state_values))
    σ_z_states  = ϕ_z * σ_bar * exp.(collect(hz_mc.state_values))

    # Allocate memory
    M = I * J * K
    z_states = Array{Float64}(I, J)
    q = Array{Float64}(I, J, J)
    Q = Array{Float64}(M, M)
    x_states = Array{Float64}(3, M)
    
    # Discretize z at each σ_z[i] and record state values for z in z_states.
    # Also, record transition probability from z_states[i, j] to 
    # z_states[i, jp] when σ_z = σ_z[i].  Store it as q[i, j, jp].
    for (i, σ_z) in enumerate(σ_z_states)
        mc_z = rouwenhorst(J, ρ, sqrt(1 - ρ^2) * σ_z, 0.0) 
        for j in 1:J
            z_states[i, j] = mc_z.state_values[j]
            for jp in 1:J
                q[i, j, jp] = mc_z.p[j, jp]  
            end
        end
    end

    # Compute x_states and Q
    for m in 1:M
        k, i, j = single_to_multi(m, I, J)
        x_states[:, m] = [σ_c_states[k], σ_z_states[i], z_states[i, j]]
        for mp in 1:M
            kp, ip, jp = single_to_multi(mp, I, J)
            Q[m, mp] = hc_mc.p[k, kp] * hz_mc.p[i, ip] * q[i, j, jp]
        end
    end

    ssyd = SSYconsumptionDiscretized(ssy,
                                     K,
                                     I,
                                     J,
                                     σ_c_states,
                                     σ_z_states,
                                     z_states,
                                     x_states,
                                     Q)
    return ssyd
end

"""
Convenience function.

"""
function discretize(ssy::SSYconsumption, int_vec)
    K, I, J = int_vec
    return discretize(ssy, K, I, J)
end





function sim_consumption(ssyd::SSYconsumptionDiscretized,
                         ts_length=1000)

    # Unpack
    σ_c_states, σ_z_states = ssyd.σ_c_states, ssyd.σ_z_states
    x_states, Q = ssyd.x_states, ssyd.Q

    M = ssyd.I * ssyd.J * ssyd.K


    mc = MarkovChain(Q, x_states)
    c_growth = Vector{Float64}(ts_length)
    z_vals = Vector{Float64}(ts_length)
    σ_c_vals = Vector{Float64}(ts_length)
    σ_z_vals = Vector{Float64}(ts_length)

    ts = simulate(mc, ts_length)
    for t in 1:ts_length
        σ_c, σ_z, z = ts[t]
        σ_c_vals[t] = σ_c
        σ_z_vals[t] = σ_z
        z_vals[t] = z
        c_growth[t] = ssy.μ + z + σ_c * randn()
    end
    
    return σ_c_vals, σ_z_vals, z_vals, c_growth
end


