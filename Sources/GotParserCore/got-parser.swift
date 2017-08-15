import Foundation
import SwiftSoup

final class GoTCharacter : CustomStringConvertible {
    var name: String = "UNKNOWN"
    var actor: String? = nil
    var order: UInt = 0
    var seasons: [UInt:Season] = [:]
    var timeOnScreenOverall: Float = 0
    
    func asCSV() -> String {
        var seasonsColumns = ""
        for seasonNumber : UInt in 1...7 {
            if let season = seasons[seasonNumber] {
                seasonsColumns += season.asCSV() + ","
            } else {
                seasonsColumns += Season().asCSV() + ","
            }
        }
        return("\(order),\(name),\(actor!),\(seasonsColumns)\(timeOnScreenOverall)")
    }
    
    var description : String {
        var seasonsString = ""
        for seasonKey in seasons.keys.sorted() {
            if (seasonsString.lengthOfBytes(using: String.Encoding.utf8) > 0) {
                seasonsString += "\n"
            }
            let season = seasons[seasonKey]!
            seasonsString += "\t\(season)"
        }
        return "\(order). \(name) performed by \(actor ?? "") appeared in the following seasons:\n\(seasonsString)\n\t\tfor \(timeOnScreenOverall) minutes overall."
    }
}

final class Season: CustomStringConvertible {
    var number : UInt = 0
    var numberOfEpisodes : UInt = 0
    var timeOnScreen : Float = 0.0
    
    func isEmpty() -> Bool {
        return (number == 0) && (numberOfEpisodes == 0) && (timeOnScreen == 0)
    }
    
    func asCSV() -> String {
        if (!isEmpty()) {
            return("\(numberOfEpisodes),\(timeOnScreen)")
        } else {
            return ","
        }
        
    }
    
    var description : String {
        return "Season \(number): \(numberOfEpisodes) episodes for \(timeOnScreen) minutes"
    }
    
}

public final class GotParser {
    private var htmlDumpURL: URL
    private var csvURL: URL
    private var characters : Array<GoTCharacter>

    public init(arguments: [String] = CommandLine.arguments) {
        if (arguments.count <= 1) {
            let scriptName = (NSURL(fileURLWithPath: arguments[0]).deletingPathExtension?.lastPathComponent) ?? ""
            print("Usage: \(scriptName) <Game-of-Thrones-IFDB-dump>")
            exit(1)
        }
        
        self.htmlDumpURL = URL(fileURLWithPath: arguments[1])
        print(htmlDumpURL)

        self.csvURL = htmlDumpURL.deletingPathExtension().appendingPathExtension("csv")
        print(csvURL)
        
        self.characters = Array()
    }
    
    public func run() throws {
        do {
            let data = try Data(contentsOf: self.htmlDumpURL)
            let html = String(data: data, encoding: String.Encoding.utf8)!
            print("Length of html = \(html.lengthOfBytes(using: String.Encoding.utf8))")
            print("parsing")
            let doc: Document = try SwiftSoup.parse(html)
            print("parsed")
            var unSortedGoTCharacters : Array<GoTCharacter> = decodeListItem(doc: doc, listItemReference: "list_item odd", expectingStartingOrder: 1)
            unSortedGoTCharacters += decodeListItem(doc: doc, listItemReference: "list_item even", expectingStartingOrder: 2)
            self.characters = unSortedGoTCharacters.sorted(by: {
                if ($0.timeOnScreenOverall > $1.timeOnScreenOverall) {
                    return true
                } else if ($0.timeOnScreenOverall < $1.timeOnScreenOverall) {
                    return false
                } else {
                    return ($0.name < $1.name)
                }
            })
            var order : UInt = 1
            for character in self.characters {
                character.order = order
                order += 1
            }
            var previousCharactersOverallScreenTime : Float = 99999
            //            var previousCharactersName = "A"
            let csvStream = OutputStream(url: self.csvURL, append: false)
            csvStream?.open()
            for character in self.characters {
                print("\(character)")
                //                assert((previousCharactersOverallScreenTime > character.timeOnScreenOverall) || (previousCharactersName < character.name))
                //                previousCharactersName = character.name
                assert(previousCharactersOverallScreenTime >= character.timeOnScreenOverall)
                previousCharactersOverallScreenTime = character.timeOnScreenOverall
                let csvLine = "\(character.asCSV())\n"
                csvStream?.write(csvLine, maxLength: csvLine.lengthOfBytes(using: String.Encoding.utf8))
            }
            csvStream?.close()
        } catch Exception.Error(let type, let message){
            print("Type:\(type), Message:\(message)")
        } catch{
            print("error")
        }
    }
    
    func decodeListItem(doc : Document, listItemReference : String, expectingStartingOrder : UInt) -> Array<GoTCharacter> {
        var expectedOrderInScreenTime : UInt = expectingStartingOrder
        var characters : Array<GoTCharacter> = Array()
        do {
            let els: Elements = try doc.getElementsByClass(listItemReference)
            for characterElement: Element in els.array(){
                let character = GoTCharacter()
                let orderInScreenTimeText = try characterElement.getElementsByClass("number").text()
                let orderInScreenTime = UInt(Float(orderInScreenTimeText)!)
                assert(expectedOrderInScreenTime == orderInScreenTime)
                character.order = orderInScreenTime
                expectedOrderInScreenTime += 2

                // Get character and actor name
                let infoElements: Elements = try characterElement.getElementsByClass("info")
                for infoElement: Element in infoElements.array() {
                    let characterLinks : Elements? = try infoElement.select("a")
                    if let characterLinks = characterLinks {
                        for characterLink in characterLinks {
                            let characterHref : String = try characterLink.attr("href")
                            if (characterHref.range(of:"character") != nil) {
                                character.name = try characterLink.text()
                            } else if (characterHref.range(of:"name") != nil) {
                                character.actor = try characterLink.text()
                            }
                            assert(character.name.lengthOfBytes(using: String.Encoding.utf8) > 0)
                        }
                    }
                    assert(character.name != "UNKNOWN")
                }
//                print("\(character.order) \(character.name)")
                
                // Get seasons
                let descriptionElements: Elements = try characterElement.getElementsByClass("description")
                for descriptionElement: Element in descriptionElements.array() {
                    let description : String = try descriptionElement.text()
//                    print("\(description)")
                    let descriptionBlocks = description.components(separatedBy: "*")
                    
                    // Get per-season information
                    var timeOnScreenOverall : Float = 0.0
                    for descriptionBlock in descriptionBlocks {
//                        print("\(descriptionBlock)")
                        let possibleSeasonalBlock = descriptionBlock.trimmingCharacters(in: .whitespacesAndNewlines)
                        if (possibleSeasonalBlock.hasPrefix("Season")) {
//                            print("\(possibleSeasonalBlock)")
                            let pattern = "^Season ([0-9]): ([0-9]{1,2}) episodes?.*<([0-9]{0,2}):?([0-9]{0,2})> ?([0-9]{0,3}):?([0-9]{0,2})?.*$"
                            let regex = try! NSRegularExpression(pattern: pattern, options: [])
                            var matches : Array = regex.matches(in:possibleSeasonalBlock, options: [], range: NSRange(location: 0, length: possibleSeasonalBlock.characters.count))
//                            print("\(matches.count) - \(matches)")
                            if (matches.count == 0) {
                                let pattern = "^Season ([0-9]): ([0-9]{1,2}) episodes?.*$"
                                let regex = try! NSRegularExpression(pattern: pattern, options: [])
                                matches = regex.matches(in:possibleSeasonalBlock, options: [], range: NSRange(location: 0, length: possibleSeasonalBlock.characters.count))
                            }
                            assert(matches.count == 1)
//                            let matchesMap = matches.map { (possibleSeasonalBlock as NSString).substring(with: $0.range) }
//                            for match in matchesMap {
//                                print("\(match)")
//                            }
                            let match = matches[0]
//                            print("number of ranges = \(match.numberOfRanges)")
                            let seasonString = (possibleSeasonalBlock as NSString)
                            assert(match.numberOfRanges == 3 || match.numberOfRanges == 7)
                            let season = Season()
                            let seasonNumber = UInt(seasonString.substring(with: match.rangeAt(1)))
                            if let seasonNumber = seasonNumber {
//                                print("\(seasonNumber)")
                                assert((seasonNumber >= 1) && (seasonNumber <= 7))
                                season.number = seasonNumber
                            } else {
                                assert(false)
                            }
                            let numberOfEpisodes = UInt(seasonString.substring(with: match.rangeAt(2)))
                            if let numberOfEpisodes = numberOfEpisodes {
//                                print("\(numberOfEpisodes)")
                                assert((numberOfEpisodes >= 1) && (numberOfEpisodes <= 10))
                                season.numberOfEpisodes = numberOfEpisodes
                            } else {
                                assert(false)
                            }
                            var timeOnScreenThisSeason : Float = 0
                            if (match.numberOfRanges > 3) {
                                var minutesForThisSeason : Int? = 0
                                let possibleMinutes = seasonString.substring(with: match.rangeAt(3))
                                if (possibleMinutes.lengthOfBytes(using: String.Encoding.utf8) > 0) {
                                    minutesForThisSeason = Int(possibleMinutes)
                                    if let minutesForThisSeason = minutesForThisSeason {
//                                        print("\(minutesForThisSeason)")
                                        assert((minutesForThisSeason >= 0) && (minutesForThisSeason <= 99))
                                    } else {
                                        print(seasonString.substring(with: match.rangeAt(4)))
                                        assert(false)
                                    }
                                } else {
//                                    print("\(minutesForThisSeason!)")
                                }
                                var secondsForThisSeason : Int? = 0
                                let possibleSeconds = seasonString.substring(with: match.rangeAt(4))
                                if (possibleSeconds.lengthOfBytes(using: String.Encoding.utf8) > 0) {
                                    secondsForThisSeason = Int(possibleSeconds)
                                    if let secondsForThisSeason = secondsForThisSeason {
//                                        print("\(secondsForThisSeason)")
                                        assert((secondsForThisSeason >= 0) && (secondsForThisSeason <= 59))
                                    } else {
                                        print(seasonString.substring(with: match.rangeAt(4)))
                                        assert(false)
                                    }
                                } else {
//                                    print("\(secondsForThisSeason!)")
                                }
                                
                                timeOnScreenThisSeason = Float(minutesForThisSeason!) + Float(secondsForThisSeason!)/60.0
//                                print("\(timeOnScreenThisSeason)")
                                assert(timeOnScreenThisSeason < 10*60)
                                season.timeOnScreen = timeOnScreenThisSeason
                                timeOnScreenOverall += timeOnScreenThisSeason
                                
                                let possibleOverallMinutes = seasonString.substring(with: match.rangeAt(5))
                                if (possibleOverallMinutes.lengthOfBytes(using: String.Encoding.utf8) > 0) {
                                    if let overallMinutes = UInt(possibleOverallMinutes) {
                                        assert((overallMinutes >= 0) && (overallMinutes <= 400))
                                        let possibleOverallSeconds = seasonString.substring(with: match.rangeAt(6))
                                        var overallSeconds : UInt = 0;
                                        if (possibleOverallSeconds.lengthOfBytes(using: String.Encoding.utf8) > 0) {
                                            if (UInt(possibleOverallSeconds) != nil) {
                                                overallSeconds = UInt(possibleOverallSeconds)!
                                                assert((overallSeconds >= 0) && (overallSeconds <= 59))
                                            } else {
                                                print("\(possibleOverallSeconds)")
                                                assert(false);
                                            }
                                        }
                                        let providedTimeOnScreenOverall = Float(overallMinutes) + Float(overallSeconds)/60.0
                                        if (providedTimeOnScreenOverall != timeOnScreenOverall) {
//                                            print("providedTimeOnScreenOverall = \(providedTimeOnScreenOverall)")
//                                            print("timeOnScreenOverall         = \(timeOnScreenOverall)")
                                            //assert(false)
                                        }
                                    }
                                }
                            }
                            if (!season.isEmpty()) {
                                if let previousActorForThisSeason = character.seasons[season.number] {
                                    if (character.actor != nil) {
                                        character.actor = character.actor! + " (and others)"
                                    } else {
                                        character.actor = "(multiple actors)"
                                    }
                                    season.numberOfEpisodes += previousActorForThisSeason.numberOfEpisodes
                                    season.timeOnScreen += previousActorForThisSeason.timeOnScreen
                                }
                                character.seasons[season.number] = season
                            }
                        }
                    }
                    character.timeOnScreenOverall = timeOnScreenOverall
                }
                // add character to our list
                characters.append(character)
            }
        } catch Exception.Error(let type, let message){
            print("Type:\(type), Message:\(message)")
        } catch{
            print("error")
        }
        return characters
    }
    
    func convertMinutesAndSecondsToMinutesAsFloat(_ minutesAndSecondsString : String) -> Float {
        var timeString = minutesAndSecondsString.trimmingCharacters(in: CharacterSet(charactersIn:"<>"))
        timeString = timeString.replacingOccurrences(of: ":15", with: ".25")
        timeString = timeString.replacingOccurrences(of: ":30", with: ".50")
        timeString = timeString.replacingOccurrences(of: ":45", with: ".75")
        if let minutesAndSeconds = Float(timeString) {
            return minutesAndSeconds
        } else {
            print("\(minutesAndSecondsString)")
            assert(false)
            return -1
        }
    }
}

//                            for n in 0..<matches[0].numberOfRanges {
//                                let range = matches[0].rangeAt(n)
//                                let value = seasonString.substring(with: range)
//                                print("\(range.location),\(range.length): \(value)")
//                            }
//                            for match in matches {
//                                for n in 0..<match.numberOfRanges {
//                                    let range = match.rangeAt(n)
//                                    let r = possibleSeasonalBlock.startIndex.advancedBy(range.location) ..<
//                                        possibleSeasonalBlock.startIndex.advancedBy(range.location+range.length)
////                                    let r = possibleSeasonalBlock.startIndex.advancedBy(range.location) ..<
////                                        possibleSeasonalBlock.startIndex.advancedBy(range.location+range.length)
//                                    possibleSeasonalBlock.substringWithRange(r)
//                                }
//                            }
//                            var seasonSections = possibleSeasonalBlock.components(separatedBy: " ")
//                            var seasonLengthSection : Int = 4
//                            var totalLengthSection : Int = 5
//                            if possibleSeasonalBlock.range(of:" (main) ") != nil {
//                                seasonLengthSection += 1
//                                totalLengthSection += 1
//                            }
//                            if (seasonSections.count < 5) {
//                                print("\(seasonSections.count)")
//                                print("\(seasonSections)")
//                                assert(false)
//                            }
//                            let seasonNumberString = seasonSections[1]
//                            if let seasonNumberOldWay = Int(seasonNumberString.substring(to:seasonNumberString.index(seasonNumberString.startIndex, offsetBy: 1))) {
//                                print ("\(seasonNumberOldWay)")
//                                if let numberOfEpisodesOldWay = Int(seasonSections[2]) {
//                                    print("\(numberOfEpisodesOldWay)")
//                                    var minutesForThisSeasonOldWay : Float
//                                    if (seasonSections.count > seasonLengthSection) {
//                                        minutesForThisSeasonOldWay = convertMinutesAndSecondsToMinutesAsFloat(seasonSections[seasonLengthSection])
//                                    } else {
//                                        minutesForThisSeasonOldWay = 0
//                                    }
//                                    print("\(minutesForThisSeasonOldWay)")
//                                    runningTime += minutesForThisSeasonOldWay
//
//                                    if ((seasonSections.count > seasonLengthSection + 1) && (seasonSections[seasonLengthSection+1] == "played")) {
//                                        while (seasonSections.count > seasonLengthSection+1) {
//                                            seasonSections.removeLast()
//                                        }
//                                        print("\(seasonSections)")
//                                    }
//
//                                    if (seasonSections.count > totalLengthSection + 2) {
//                                        print("\(seasonSections.count)")
//                                        print("\(totalLengthSection + 4)")
//                                        assert(seasonSections.count == totalLengthSection + 4)
//                                        let totalMinutes = convertMinutesAndSecondsToMinutesAsFloat(seasonSections[totalLengthSection])
//                                        if (totalMinutes > 0) {
//                                            print("\(totalMinutes)")
//                                            if (totalMinutes != runningTime) {
//                                                print("\(runningTime)")
//                                                assert(false)
//                                            }
//                                        } else {
//                                            assert(false)
//                                        }
//                                    }
//                                } else {
//                                    assert(false)
//                                }
//                            } else {
//                                assert(false)
//                            }

