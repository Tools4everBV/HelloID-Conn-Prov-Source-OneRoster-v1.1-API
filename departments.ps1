[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12;

$config = @{
    BaseUri = "https://{base url}";
    VersionUri = "/ims/oneroster/v1p1";
    TokenUri = "/oauth/token";
    ClientKey = "{Client Secret";
    ClientSecret = "{Client Key}";
    PageSize = "1000";
}

function Get-AuthToken {
[cmdletbinding()]
Param (
[string]$BaseUri, 
[string]$VersionUri, 
[string]$TokenUri, 
[string]$ClientKey,
[string]$ClientSecret,
[string]$PageSize
   ) 
    Process 
    {
        $requestUri = "$($BaseURI)$($TokenURI)" 
        
        $pair = $ClientKey + ":" + $ClientSecret;
        $bytes = [System.Text.Encoding]::ASCII.GetBytes($pair);
        $bear_token = [System.Convert]::ToBase64String($bytes);
        $headers = @{ Authorization = "Basic " + $bear_token; Accept = "application/json";};
        
        $parameters = @{
                grant_type="client_credentials";
        };
        Write-Verbose "POST $($requestUri)" -Verbose;
        $response = Invoke-RestMethod -Method Post -Uri $requestUri -Body $parameters -Headers $headers -Verbose:$false
        Write-Verbose -Verbose $response;
        $accessToken = $response.access_token
    
        #Add the authorization header to the request
        $authorization = @{
                Authorization = "Bearer $($accesstoken)";
                'Content-Type' = "application/json";
                Accept = "application/json";
            }
        @($authorization);
    }
}

function Get-Data {
[cmdletbinding()]
Param (
[string]$BaseUri, 
[string]$VersionUri, 
[string]$TokenUri, 
[string]$ClientKey,
[string]$ClientSecret,
[string]$PageSize,
[string]$EndpointUri,
[object]$Authorization

   ) 
    Process 
    {
        $offset = 0;
        $requestUri = "$($BaseURI)$($VersionUri)$($EndPointUri)" 
        $results = [System.Collections.ArrayList]@();
        while($true)
        {
        $parameters = @{
                limit=$PageSize;
                offset=$offset;
        };
        Write-Verbose "GET $($requestUri) ($($offset))" -Verbose;

        $propertyArray = $EndpointURI.replace('/','');
        if(@("students","teachers") -contains $propertyArray) { $propertyArray = "users" }
        
        $response = (Invoke-RestMethod -Method GET -Uri $requestUri -Body $parameters -Headers $Authorization -Verbose:$false)."$($propertyArray)"
        
        $results.AddRange($response);

        if($response.count -lt $offset)
        {
            break;
        }
        
        $offset = $offset + $response.count;
        
     }
        return $results;

    }
}

$authorization = Get-AuthToken @config
$orgs = Get-Data @config -EndpointUri "/orgs" -Authorization $authorization

foreach($org in $orgs)
{
    $department = @{
        ExternalId=$org.sourcedId;
        DisplayName=$org.name;
        Name=$org.Name;
        Identifier=$org.identifier;
        Type=$org.type;
    }

    $department | ConvertTo-Json
}

Write-Verbose -Verbose "Department import completed";
