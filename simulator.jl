## STDLIB
using Random
using DelimitedFiles
using Distributed
using Base.Filesystem
## ADDED PACKAGES
using ClusterManagers
using DataFrames
using CSV
using JSON

## call all the using in main package to trigger precompilation 
## the precompilation files will get shared amongst all nodes so won't clash with `@everywhere` triggering precompilation
using Parameters      ## with julia 1.1 this is now built in.
using ProgressMeter   ## can now handle parallel with progress_pmap
#using PmapProgressMeter
#using DataFrames
using Distributions
using StatsBase
using StaticArrays
#using BenchmarkTools

## include
#include("Influenza.jl")
#using .InfluenzaModel
    
addprocs(SlurmManager(544), partition="defq", N=17)


@everywhere include("Influenza.jl")
@everywhere using .InfluenzaModel

function dataprocess(results, P::InfluenzaParameters, numberofsims; directory="./Results/")    
    ## if the directory argument is passed without a trailing slash, 
    ## it becomes a prepend to the filename.
    
    resultsL      = zeros(Int64, P.sim_time, numberofsims)
    resultsA      = zeros(Int64, P.sim_time, numberofsims)
    resultsS      = zeros(Int64, P.sim_time, numberofsims)
    resultsR0     = zeros(Int64, numberofsims)
    resultsSymp   = zeros(Int64, numberofsims)
    resultsAsymp  = zeros(Int64, numberofsims)
    resultsNumAge = zeros(Int64, P.grid_size_human, numberofsims)
    resultsFailVector = zeros(Int64, P.grid_size_human, numberofsims)    
    resultsInfOrNot = zeros(Int64, P.grid_size_human, numberofsims)    
    VacStatus = zeros(Int64, P.grid_size_human, numberofsims)

    Infection_Matrix = zeros(Int64, 15, 15)
    Fail_Matrix = zeros(Int64, 15, 15)
    Infection_Matrix_average = zeros(Float64, 15, 15)
    Contact_Matrix_General = zeros(Float64, 15, 15)
  
    for i=1:numberofsims
        resultsL[:,i] = results[i][1]
        resultsS[:,i] = results[i][2]
        resultsA[:,i] = results[i][3]
      
        resultsR0[i] = results[i][4]
        resultsSymp[i] = results[i][5]
        resultsAsymp[i] = results[i][6]

        Infection_Matrix = Infection_Matrix + results[i][7]
        Fail_Matrix =  Fail_Matrix + results[i][8]
        Contact_Matrix_General = Contact_Matrix_General + results[i][9]

        resultsNumAge[:,i] = results[i][10]
        resultsFailVector[:,i] = results[i][11]
        resultsInfOrNot[:,i] = results[i][12]
        VacStatus[:,i] = results[i][13]
    end

    
    Infection_Matrix = Infection_Matrix/numberofsims
    Fail_Matrix =  Fail_Matrix/numberofsims
    Contact_Matrix_General = Contact_Matrix_General/numberofsims
    

    if !Base.Filesystem.isdir(directory)
        Base.Filesystem.mkpath(directory)
    end

    writedlm(string("$directory", "_latent.dat"), resultsL)
    writedlm(string("$directory", "_symp.dat"),resultsS)
    writedlm(string("$directory", "_asymp.dat"),resultsA)
    writedlm(string("$directory", "_R0.dat"),resultsR0)
    writedlm(string("$directory", "_SympInf.dat"),resultsSymp)
    writedlm(string("$directory", "_AsympInf.dat"),resultsAsymp)
    writedlm(string("$directory", "_InfMatrix.dat"),Infection_Matrix)
    writedlm(string("$directory", "_FailMatrix.dat"),Fail_Matrix)
    writedlm(string("$directory", "_ContactMatrixGeneral.dat"),Contact_Matrix_General)
    writedlm(string("$directory", "_NumAgeGroup.dat"),resultsNumAge)
    writedlm(string("$directory", "_FailVector.dat"),resultsFailVector)
    writedlm(string("$directory", "_InfOrNot.dat"),resultsInfOrNot)
    writedlm(string("$directory", "_VacStatus.dat"),VacStatus)
    JSON.print(open(string("$directory", "parameters.dat"), "w"), P, 4)
end


function run_calibration_R0()
    error("not implemented")
end

function run_calibration_attackrate()
    ## calibrating to attack rate simply is running the full simulations 
    ## and then seeing the number of symptomatics at the end
    ## the full simulations are run over a range of beta values.     
    beta_range = 0.01:0.001:0.05
    for i in beta_range
        println("starting simulation for i: $i")
        ## do not add the trailing slash to have "beta_0_0x" appended to the filename
        dname = "./Calibration/beta_$(replace(string(i), "." => "_"))"
        #println(dname)
        @everywhere P = InfluenzaParameters(sim_time = 250, vaccine_efficacy = 0.0, transmission_beta=$i)        
        results = pmap(x -> main(x, P), 1:500)
        println("... processing results")
        dataprocess(results, P, 500, directory=dname)   
    end
    println("calibration finished")
end

function run_single_beta(beta; process=true) 
    ### runs 500 simulations with a particular beta value.    
    @everywhere P = InfluenzaParameters(vaccine_efficacy = 0.0, transmission_beta=$beta)  
    results = pmap(x -> main(x, P), 1:500)        
    if process
        dataprocess(results, P, 500)
    end
    return results
end

function run_attackrate(;process=true)
    ### runs 500 simulations with a particular attack rate. 
    # we use the regression formula (y + 0.234616)/11.668 (from calibration) to estimate the beta value.
    ars = [0.04]
    ves = [0.4 0.5 0.6 0.7 0.8]
    f(y) = round((y + 0.234616)/11.668, digits = 4)    
    for ar in ars, ve in ves
        #randdir = randstring()
        β = f(ar)
        dname =  "./ar_$(replace(string(ar), "." => "_"))_ve_$(replace(string(ve), "." => "_"))/"
        println("starting simulations for β=$β, ar=$ar, ve=$ve...")  
        @everywhere P = InfluenzaParameters(sim_time = 250, vaccine_efficacy = $ve, transmission_beta=$β)          
        results = pmap(x -> main(x, P), 1:500)
        println("simulations for β=$β ended...")    
        if process
            println("starting dataprocess β=$β, ar=$ar, ve=$ve ended...")   
            dataprocess(results, P, 500, directory=dname)
        end
    end      
end

