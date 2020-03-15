function _solve(algo::BATSampling, alphas, omegas, B, b, phi_bounds, basis)
    sig = transpose(alphas.alphas) * omegas
    sig_inv = sym_inv(sig)
    model = phi -> LogDVal(algo.log_data_distribution(phi.phi) + log_bounds_correction(phi.phi, phi_bounds))
    @assert !isapprox(det(sig)+1, 1) "Sigma matrix is singular"
    prior = NamedTupleDist(phi = MvNormal(phi_bounds.initial, sig_inv))
    posterior = BAT.PosteriorDensity(model, prior)
    @info "Starting sampling"
    samples = BAT.bat_sample(posterior, (algo.nsamples, algo.nchains), algo.algo).result;
    samples_mode = BAT.mode(samples).phi
    samples_cov = BAT.cov(unshaped.(samples))
    @info "Solved with BAT.jl"
    return PhiVec(samples_mode, basis, samples_cov, alphas.alphas)
end
