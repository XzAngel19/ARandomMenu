-- Reference-space coordinates are pixels on the supplied 614 x 550 image.
return {
    Name = "ViolentReferenceUI",
    Identity = "ARandomMenu.Violent.UIOnly.v1",
    Pink = Color3.fromRGB(255, 0, 157),
    Selection = Color3.fromRGB(255, 77, 183),
    White = Color3.fromRGB(241, 245, 246),
    Muted = Color3.fromRGB(209, 215, 218),
    Black = Color3.fromRGB(7, 7, 9),
    Panel = Color3.fromRGB(18, 21, 23),
    BodyFont = Enum.Font.SourceSans,
    DisplayFont = Enum.Font.RobotoCondensed,
    -- A built-in condensed bold face; no custom font/image downloads.
    DisplayFace = Font.new("rbxasset://fonts/families/RobotoCondensed.json",
        Enum.FontWeight.Bold, Enum.FontStyle.Normal),
}
