source $oldFishDir/config.fish
functions -c fish_prompt _oldFishPrompt

function fish_prompt
    set_color red
    echo -n "[RE]"
    _oldFishPrompt
end