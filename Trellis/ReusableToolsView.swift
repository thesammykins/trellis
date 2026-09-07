import SwiftUI

struct ReusableToolsView: View {
    let store: ReusableAgentTools
    @Environment(\.dismiss) private var dismiss
    @State private var approved: [ApprovedReusableTool] = []
    @State private var proposals: [MemoryProposal] = []
    @State private var error: String?
    @State private var busy = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Reusable Tools").font(.title2)
                Spacer()
                Button("Refresh") { Task { await refresh() } }.disabled(busy)
                Button("Done") { dismiss() }
            }
            Text(store.directory.path).font(.caption.monospaced()).textSelection(.enabled)
            Text("The agent can propose exact commands and improvements. Applying a version makes it available; every run still needs execution and output approval.")
                .font(.callout).foregroundStyle(.secondary)
            if let error { Text(error).foregroundStyle(.orange).textSelection(.enabled) }
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Approved").font(.headline)
                    if approved.isEmpty { Text("No approved tools yet. Ask the agent to propose a reusable tool.").foregroundStyle(.secondary) }
                    ForEach(approved) { tool in
                        DisclosureGroup(tool.recipe.name + " · Version \(tool.revision)" + (tool.recipe.enabled ? "" : " · Disabled")) {
                            Text(tool.recipe.reviewText).font(.callout.monospaced()).textSelection(.enabled)
                            Button(tool.recipe.enabled ? "Disable Tool" : "Enable Reviewed Tool") {
                                busy = true
                                Task {
                                    do { try await store.setEnabled(!tool.recipe.enabled, snapshot: tool); await refresh() }
                                    catch { self.error = error.localizedDescription }
                                    busy = false
                                }
                            }.disabled(busy)
                            Text("ID: \(tool.id.uuidString.lowercased())\nApproved hash: \(tool.hash)")
                                .font(.caption.monospaced()).foregroundStyle(.secondary).textSelection(.enabled)
                        }
                    }
                    Divider()
                    Text("Proposals").font(.headline)
                    if proposals.filter({ $0.status == "proposed" || $0.status == "stale" }).isEmpty {
                        Text("No proposals waiting for review.").foregroundStyle(.secondary)
                    }
                    ForEach(proposals.filter { $0.status == "proposed" || $0.status == "stale" }) { proposal in
                        proposalReview(proposal)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(20).frame(minWidth: 640, idealWidth: 720, minHeight: 500, idealHeight: 650)
        .task { await refresh() }
    }

    @ViewBuilder
    private func proposalReview(_ proposal: MemoryProposal) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(proposal.title).font(.headline)
            Text(proposal.status == "stale" ? "Stale · request a new proposal against the current version" : "Pending review")
                .font(.caption).foregroundStyle(.secondary)
            Text("Source: " + proposal.source).font(.caption).textSelection(.enabled)
            if let current = approved.first(where: { $0.id == proposal.pageID }) {
                Text("Current approved version \(current.revision)").font(.subheadline.weight(.semibold))
                Text(current.recipe.reviewText).font(.callout.monospaced()).textSelection(.enabled)
                Text("Proposed replacement").font(.subheadline.weight(.semibold))
            } else { Text("New tool").font(.subheadline.weight(.semibold)) }
            if let recipe = try? ReusableToolRecipe.decode(proposal.body) {
                Text(recipe.reviewText).font(.callout.monospaced()).textSelection(.enabled)
            } else {
                Text("Invalid recipe. This proposal cannot be applied.").foregroundStyle(.orange)
                Text(proposal.body).font(.caption.monospaced()).textSelection(.enabled)
            }
            HStack {
                Button("Reject") { review(proposal, approve: false) }
                Spacer()
                Button("Apply Reviewed Version") { review(proposal, approve: true) }
                    .buttonStyle(.borderedProminent)
                    .disabled(proposal.status != "proposed" || (try? ReusableToolRecipe.decode(proposal.body)) == nil)
            }
            .disabled(busy)
        }
        .padding(12)
        .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Review reusable tool " + proposal.title)
    }

    private func review(_ proposal: MemoryProposal, approve: Bool) {
        busy = true
        Task {
            do {
                if approve { try await store.approve(proposal) }
                else { try await store.reject(proposal.id) }
                await refresh()
            } catch {
                self.error = error.localizedDescription
            }
            busy = false
        }
    }

    private func refresh() async {
        var failures: [String] = []
        do { approved = try await store.approved() }
        catch { approved = []; failures.append(error.localizedDescription) }
        do { proposals = try await store.proposals() }
        catch { proposals = []; failures.append(error.localizedDescription) }
        error = failures.isEmpty ? nil : failures.joined(separator: "\n")
    }
}
