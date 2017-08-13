import GotParserCore
let tool = GotParser()
do {
    try tool.run()
} catch {
    print("Whoops! An error occurred: \(error)")
}
