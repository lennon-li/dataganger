# DataGangeR TODO

## Reusable frozen contracts for repeated synthetic generation

- [ ] Evolve the human-approved synthesis contract into a reusable, frozen generator artifact.
- [ ] Keep privacy-sensitive decisions immutable after approval: variable roles, exclusions, transformations, synthesis methods, disclosure constraints, naming rules, and other policy choices must not change silently.
- [ ] Require a new human review/approval cycle whenever the frozen contract itself changes.
- [ ] Allow both human users and Agents to generate multiple synthetic datasets from the same approved contract.
- [ ] Permit only explicitly allowed generation-time variation, such as random seed, sample size, number of datasets, and later any human-approved scenario parameters.
- [ ] Provide a narrow R API for repeated generation, e.g. `generate_synthetic(contract, seed = ..., n = ...)`.
- [ ] Provide an Agent/CLI interface for the same operation without exposing the original records to the Agent.
- [ ] Define the trust boundary clearly: the Agent may invoke the approved generator, but must not gain direct access to the real dataset or alter the frozen privacy contract.
- [ ] Evaluate whether the fitted generator artifact itself can leak sensitive information; include generator-export risk in the human privacy review before allowing Agent access.
- [ ] Support the intended development loop: Agent prototypes programs using multiple permitted synthetic-data variations; the human validates the resulting program on synthetic data and, inside the trusted environment, on the real data.
- [ ] Add provenance/versioning so every generated dataset records the contract version, generator version, seed, requested size, and relevant generation parameters.
- [ ] Add tests proving that repeated generation cannot mutate the approved contract and that Agent-facing generation paths do not require direct access to the original records.

### Target workflow

`Real data -> Shiny-guided human review -> Approved/frozen contract -> Reusable generator -> Synthetic dataset 1, 2, 3... -> Agent prototypes -> Human validates on synthetic and real data`

### Design principle

**Human defines the privacy boundary. DataGangeR freezes it. Users and Agents can then generate permitted synthetic variations repeatedly without allowing the Agent to rewrite the privacy policy.**
