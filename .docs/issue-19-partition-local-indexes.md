# Partition-local Multigraph queries and index maintenance

This change ports the graph implementation measured in the [Runic issue #19 foundation comparison](https://github.com/zblanco/runic/pull/20) into its owning repository. It targets `zw/multigraph-fork`, the maintenance branch for the Multigraph package. The base is `424928f` (0.16.1-mg.4). Before porting, `lib/multigraph.ex` matched the original locked package byte-for-byte; the patched runtime source matches Runic's measured foundation byte-for-byte.

## Implementation

Filtered incoming, outgoing and incident-edge queries now begin with `edge_index[partition][endpoint]` candidate pairs instead of materializing all adjacency and then intersecting. One helper checks direction, finds canonical current vertex values, inspects the labels on selected pairs and applies the partition predicate. Undirected queries include both incident orientations, and self loops appear once. Stale candidate keys are skipped defensively.

Relabel/delete operations update the affected endpoint sets and remove empty entries instead of rebuilding an entire partition. Since the index stores endpoint pairs rather than individual labels, a surviving parallel label can still own a shared partition membership. Refreshing memberships accounts for label collisions and custom partitions based on edge weight or properties. Deletion also clears the corresponding properties so reinsertion cannot revive obsolete partition metadata.

This is the same pure persistent graph representation. It adds no graph fields, process, ETS table or separate direction index. Existing valid graph storage has the same shape. If an older operation already left a custom index stale, rebuild it from canonical records before relying on complete indexed results.

## Cost model

Let H be unrelated incident history, C the selected incident candidate pairs, L the labels on those pairs, and K the endpoint entries in an affected partition. Persistent map/set operations and custom partition-function costs remain part of the model.

| Operation | Before | After |
|---|---|---|
| Partition-filtered incident/in/out query | Materializes O(H + C) adjacency first | Visits selected C pairs and their L labels |
| Remove a pair membership | Rebuilds O(K) endpoint entries | Updates at most two endpoint maps/sets |
| Repeated activation relabels | Repeated partition-wide scans introduce a quadratic term | Local pair/membership updates and persistent-map paths |

Incoming queries can still examine opposite-direction candidates within the selected partition. Many labels sharing one pair still cost work. A directional or per-label reference-count index could reduce that work, but would add state and mutation obligations; this patch keeps the existing representation.

Unfiltered queries still return all requested history. This patch does not reclaim facts, edges or payloads, compact dispatch contexts, or reduce serialized graph size. Runic's separate compact-dispatch changes are complementary; their combined workflow gains must not be attributed to this graph patch alone.

## Evidence

The original comparison ran identical graph probes against the locked baseline and patched dependency, serially, with warmup and three independent-process timing samples. Setup, process creation/copy, explicit GC and result-size inspection were outside timing. Elixir 1.19.5 / OTP 28; 16 schedulers. Raw historical samples are under `issue-19-partition-results/`.

| Operation at n=2,048 | Baseline median | Indexed median | Baseline / indexed BEAM reductions |
|---|---:|---:|---:|
| 500 filtered incoming queries, selected degree one | 292.363 ms | 0.196 ms | 16,077,123 / 52,269 |
| Relabel all 2,048 activations | 167.753 ms | 5.998 ms | 21,393,394 / 397,774 |

The indexed 8,192-activation relabel probe takes 29.685 ms / 1,535,414 reductions. Short wall times fluctuate; the reduction counts support the local-operation analysis. These are observations, not universal constant-time hash-map claims. Post-GC process memory is a retained worker/closure/result metric, not peak allocation or process-tree memory.

The companion Runic comparison improves 2,048-item map/collect from 6,275.748 ms to 174.246 ms and sampled peak memory from 111.103 to 15.607 MiB **when this graph patch is combined with compact dispatch**. Graph changes alone measured 4,086.500 ms and 92.626 MiB. Both combined workflows retain the same 4,098 facts and 8,203 edges.

## Correctness and remaining boundary

Twenty new contract tests reconstruct expected partition membership from canonical edge records and compare full edge structs, direction and properties. They cover directed/undirected graphs, custom identifiers, self loops, parallel labels, overlapping custom partitions, metadata updates, relabel collisions, deletion/reinsertion, vertex deletion and fixed-seed mutation traces. The repository's existing property tests and doctests also run in the full suite; no duplicate copy of its upstream doctests is added.

The original changed-ID `replace_vertex/3` implementation can leave stale indexes. Repairing that separate operation is outside this patch; a regression ensures the new filtered queries skip stale candidates without introducing an exception. Same-ID replacement, used by Runic's composition, reads current canonical vertex values and is covered.

## Reproduction

```sh
mix test
mix test test/multigraph_index_contract_test.exs
mix format --check-formatted lib/multigraph.ex test/multigraph_index_contract_test.exs bench/partition_indexes.exs
mix run bench/partition_indexes.exs 128 512 2048 8192
```

To reproduce the baseline, invoke this script by absolute path from an isolated worktree at `424928f` with its own dependencies/build directory. The first four probe operations repeat 500 times; `consume_all` performs n distinct relabels. The PR does not bump the package version or publish a release. Runic can pin the reviewed commit during integration and move to a released version afterward.

## Fresh native validation

The full native suite passes **114 doctests and 117 tests, zero failures** in 94.7 seconds, including the existing property tests and twenty new index contract cases. Changed files pass formatting and whitespace checks. The fresh native probe completes all 60 rows (three samples for each operation/size through n=8,192); at n=2,048, filtered incoming queries take a median 0.324 ms for 500 calls and consume-all takes 5.977 ms. These fresh timings are kept separate from the historical comparison. See [the test log](issue-19-partition-results/tests.txt) and [native probe](issue-19-partition-results/native.csv).
