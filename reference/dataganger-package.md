# DataGangeR uses two synthesis engines. By default the engine is chosen automatically from your objective: demo uses the dependency-free internal engine, development uses synthpop when it is installed so moderate correlations can be preserved, and analytics requires synthpop plus an explicit risk acknowledgement because high-fidelity synthesis may retain sensitive structure. The engine can also be selected explicitly (auto, internal, or synthpop) in both the Shiny app and the CLI. Install synthpop with `install.packages("synthpop")` to enable relationship-preserving synthesis at full fidelity. When synthpop is used, please cite: Nowok B, Raab GM, Dibben C (2016). "synthpop: Bespoke Creation of Synthetic Data in R." *Journal of Statistical Software*, 74(11), 1-26. doi:10.18637/jss.v074.i11

Creates synthetic data doubles from real datasets for prototyping,
teaching, 'shiny' development, and AI-assisted programming. Provides
data profiling, role detection, configurable synthesis, utility
comparison, and disclosure-risk warnings. Synthetic outputs are intended
to reduce direct disclosure risk, not to guarantee privacy.

## See also

Useful links:

- <https://lennon-li.github.io/dataganger/>

- <https://github.com/lennon-li/dataganger>

- Report bugs at <https://github.com/lennon-li/dataganger/issues>

## Author

**Maintainer**: Lennon Li <yeli@biostats.ai>

Authors:

- Lennon Li <yeli@biostats.ai>
