# Poshbot - A simple API based bot framework for hipchat
# t.r.parkinson@sheffield.ac.uk
# requires -version 3.0

# Requires https://github.com/timparkinson/posh-hipchat

#region Invoke
function Start-Poshbot {
    [CmdletBinding(DefaultParameterSetName='File')]

    param(
        [Parameter(ParameterSetName='File')]
        $TokenPath=(Join-Path -Path $PSScriptroot -ChildPath 'token.txt'),
        [Parameter(ParameterSetName='Token')]
        $Token,
        [Parameter()]
        [String]$Name = 'Poshbot',
        [Parameter(Mandatory=$true)]
        [String]$Room,
        [Parameter()]
        [Scriptblock]$ScriptBlock={
            #Just echo what is said back to the room
            "@$from $instruction"
        },
        [Parameter()]
        $Sleep = 10,
        [Parameter()]
        $MessageHashFilePath = (Join-Path -Path $PSScriptroot -ChildPath 'messages.txt')
    )

    begin {

        Write-Verbose "Setting up"
        $messages_to_me_history = @{}
        if (-not (Test-Path -Path $MessageHashFilePath -IsValid)) {
            throw "Problem with Message Hash File Path"
        } elseif (Test-Path -Path $MessageHashFilePath) {
            Get-Content -Path $MessageHashFilePath |
                ForEach-Object {
                    $messages_to_me_history.$_ = $true   
            }
        }

        if (-not $Token) {
            if (Test-Path -Path $TokenPath) {
                $Token = Get-Content -Path $TokenPath
            } else {
                throw "Token file not found"
            }
        }

        $hash_algorithm = 'SHA1'
        $hasher = [System.Security.Cryptography.HashAlgorithm]::Create($hash_algorithm)
        $encoder = New-Object System.Text.UTF8Encoding
    
        
    }

    process {
        Write-Verbose "Entering Loop"
        while ($true) {
            $hipchat_history = Get-HipChatHistory -Room $Room -Token $Token

            $hipchat_history | 
                Where-Object {$_.message -match "(@)?$Name (?<instruction>.*)" } | 
                        ForEach-Object {
                            Write-Verbose "Matched a message"
                            $string_builder = New-Object System.Text.StringBuilder
                            $message_hash = $hasher.ComputeHash($encoder.GetBytes("$($_.date)$($_.from)$($_.message)"))
                            $message_hash |
                                ForEach-Object {
                                    [void]$string_builder.Append($_.ToString("x2"))
                                }
                            $message_hash_string = $string_builder.ToString()

                            Write-Verbose "Hash: $message_hash_string"
                            if (-not $messages_to_me_history.$message_hash_string) {
                                $messages_to_me_history.$message_hash_string = $true
                                $message_hash_string | Out-File -FilePath $MessageHashFilePath -Append
                                $from = $_.from.name -replace ' ', ''
                                $instruction = $matches.instruction

                                Write-Verbose "Attempting to run ScriptBlock for $from ($instruction)"
                                try {
                                    $reply = Invoke-Command -ScriptBlock {
                                        param($from,$instruction)
                                        $ScriptBlock.Invoke()
                                    } -ArgumentList $from,$instruction

                                    Send-HipChatMessage -Message $reply -Room $Room -From $Name -Token $Token
                                }

                                catch {
                                    Write-Error "Problem invoking scriptblock for message from @$from"
                                    Send-HipChatMessage -Message "@$from (problem) Error executing command" -Room $Room -From $Name -Token $Token
                                }
                            } else {
                                Write-Verbose "Hash already stored"
                            }
                }
                Start-Sleep -Seconds $Sleep
            }
    }

    end {}
}
#endregion



