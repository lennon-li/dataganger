# DataGangeR uses two synthesis engines. By default the engine is chosen automatically from your objective: the analytics purpose (and any high-fidelity setting), where preserving relationships between variables matters, uses the synthpop package (Nowok, Raab & Dibben, 2016); other objectives use a dependency-free internal marginal engine. In the Shiny app the engine can also be selected explicitly (auto, internal, or synthpop). Install synthpop with `install.packages("synthpop")` to enable relationship-preserving synthesis at full fidelity.

When synthpop is used, please cite: Nowok B, Raab GM, Dibben C (2016).
"synthpop: Bespoke Creation of Synthetic Data in R." *Journal of
Statistical Software*, 74(11), 1-26. doi:10.18637/jss.v074.i11

## See also

Useful links:

- <https://lennon-li.github.io/dataganger/>

- <https://github.com/lennon-li/dataganger>

- Report bugs at <https://github.com/lennon-li/dataganger/issues>

## Author

**Maintainer**: Lennon Li <yeli@biostats.ai>

Authors:

- Lennon Li <yeli@biostats.ai>
