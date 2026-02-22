import Testing
@testable import CodexMonitorCore

@Test("Roadmap mapping uses corporate root")
func roadmapMappingCorporate() {
  let mapping = ProjectMapping.default
  let mapper = RoadmapMapper(mapping: mapping)
  let project = mapper.projectForRepoPath("~/Developer/promptping-ai/bxl-ping")
  #expect(project?.projectId == mapping.project3Id)
}

@Test("Roadmap mapping uses client root")
func roadmapMappingClient() {
  let mapping = ProjectMapping.default
  let mapper = RoadmapMapper(mapping: mapping)
  let project = mapper.projectForRepoPath("~/Developer/rossel/some-repo")
  #expect(project?.projectId == mapping.project4Id)
}
