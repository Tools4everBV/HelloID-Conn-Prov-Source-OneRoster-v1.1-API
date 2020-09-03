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
$academicSessions = Get-Data @config -EndpointUri "/academicSessions" -Authorization $authorization
$enrollments = Get-Data @config -EndpointUri "/enrollments" -Authorization $authorization
$classes = Get-Data @config -EndpointUri "/classes" -Authorization $authorization
$courses = Get-Data @config -EndpointUri "/courses" -Authorization $authorization

#User can be used instead if guardians or other roles are needed.
#$users = Get-Data @config -EndpointUri "/users" -Authorization $authorization
$students = Get-Data @config -EndpointUri "/students" -Authorization $authorization
$teachers = Get-Data @config -EndpointUri "/teachers" -Authorization $authorization

$availablePersons = [System.Collections.ArrayList]@();
$availablePersons.AddRange($students);
$availablePersons.AddRange($teachers);

foreach($user in $availablePersons)
{  
    $person = @{};
    $person['ExternalId'] = "$($user.sourcedId)";
    $person['DisplayName'] = "$($user.givenName) $($user.familyName) ($($user.sourcedId))";

    foreach($prop in $user.PSObject.properties)
    {
        if(@("orgs","grades","userIds","agents") -contains $prop.Name) { continue; }
               
        $person[$prop.Name] = "$($prop.Value)";
        
    }

    $person['orgs'] = $user.orgs.sourcedId;
    $person['grades'] = $user.grades;
    $person['userIds'] = $user.userIds;
    $person['agents'] = $user.agents.sourcedId;

    $person['Contracts'] = [System.Collections.ArrayList]@();

    foreach($e in $enrollments)
    {
        if($e.user.sourcedId -eq $user.sourcedId)
        {
            $contract = @{};
            foreach($prop in $e.PSObject.properties)
            {
                if(@("class","school","user") -contains $prop.Name) { continue; }
                $contract[$prop.Name] = "$($prop.Value)";
            }

            foreach($c in $classes)
            {
                if($e.class.sourcedId -eq $c.sourcedId)
                {
                    #Class for Enrollment
                    $contract['class'] = @{};
                    foreach($prop in $c.PSObject.properties)
                    {
                        if(@("subjects","course","school","terms","subjectCodes","periods") -contains $prop.Name) { continue; }
                        $contract.class[$prop.Name] = "$($prop.Value)";
                    }

                    #Academic Sessions for Class
                    $contract['terms'] = [System.Collections.ArrayList]@();
                    foreach($as in $academicSessions)
                    {
                        if($c.terms.sourcedId -contains $as.sourcedId)
                        {
                            $term = @{};
                            foreach($prop in $as.PSObject.properties)
                            {
                                if(@("parent") -contains $prop.Name) { continue; }
                                $term[$prop.Name] = "$($prop.Value)";
                            }
                            [void]$contract['terms'].Add($term);
                        }
                    }

                    #Course for Class
                    $contract['course'] = @{};
                    foreach($crs in $courses)
                    {
                        if($c.course.sourcedId -contains $crs.sourcedId)
                        {
                            foreach($prop in $crs.PSObject.properties)
                            {
                                if(@("org","grades","subjectCodes","schoolYear") -contains $prop.Name) { continue; }
                                $contract.course[$prop.Name] = "$($prop.Value)";
                            }
                        }
                    }
                    break;
                }
            }

            [void]$person.Contracts.Add($contract);
        }
    }
    
    $person | ConvertTo-Json -Depth 50

}
