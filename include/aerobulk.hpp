/* -*- mode: c++; coding: utf-8; tab-width: 4; indent-tabs-mode: nil; c-basic-offset: 4; show-trailing-whitespace: t -*- vim: set fenc=utf-8 ft=cpp et sw=4 ts=4 sts=4: */

#ifndef __aerobulk_HPP
#define __aerobulk_HPP 1

#include <vector>
#include <string>
#include <cassert>
#include <cstdarg>

namespace aerobulk
{
    enum class algorithm
    {
        OTHER   = 0, // In case you want to roll your own
        COARE   = 1,
        COARE35 = 2,
        NCAR    = 3,
        ECMWF   = 4
    };

    std::string algorithm_to_string(algorithm algo);

    // To check the size of the inputs
    int check_sizes(int count, ...);

    // Interface for lvap
    std::vector<double> lvap(const std::vector<double> &sst);

    // Interface to aerobulk_model with rad_sw and rad_lw as inputs and T_s as output
    void model(algorithm algo, double zt, double zu, const std::vector<double> &sst, const std::vector<double> &t_zt,
        const std::vector<double> &q_zt, const std::vector<double> &U_zu, const std::vector<double> &V_zu, const std::vector<double> &slp,
        std::vector<double> &QL, std::vector<double> &QH, std::vector<double> &Tau_x, std::vector<double> &Tau_y,
        const std::vector<double> &rad_sw, const std::vector<double> &rad_lw, std::vector<double> &T_s,
        const int Niter=5);

    // Interface to aerobulk_model without rad_sw, rad_lw, and T_s
    void model(algorithm algo, double zt, double zu, const std::vector<double> &sst, const std::vector<double> &t_zt,
        const std::vector<double> &q_zt, const std::vector<double> &U_zu, const std::vector<double> &V_zu, const std::vector<double> &slp,
        std::vector<double> &QL, std::vector<double> &QH, std::vector<double> &Tau_x, std::vector<double> &Tau_y,
        const int Niter=5);
}

#endif
