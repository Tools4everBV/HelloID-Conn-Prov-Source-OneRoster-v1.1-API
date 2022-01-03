[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12;

$config = ConvertFrom-Json $configuration

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
        
        $response = (Invoke-RestMethod -Method GET -Uri $requestUri -Body $parameters -Headers $Authorization)."$($propertyArray)"
        
        $results.AddRange($response);
        
        $offset = $offset + $response.count;
        if($response.count -lt $PageSize)
        {
            break;
        }
        
        
        
     }
        return $results;

    }
}

try 
{
    $splat = @{
        BaseURI = $config.BaseURI
        VersionUri = $config.VersionUri
        TokenUri = $config.TokenUri
        ClientKey = $config.ClientKey
        ClientSecret = $config.ClientSecret
        PageSize = $config.PageSize
    }
    $splat['Authorization'] = Get-AuthToken @splat
    $orgs = Get-Data @splat -EndpointUri "/orgs"
    $academicSessions = Get-Data @splat -EndpointUri "/academicSessions"
    $enrollments = Get-Data @splat -EndpointUri "/enrollments"
    $classes = Get-Data @splat -EndpointUri "/classes"
    $courses = Get-Data @splat -EndpointUri "/courses"

    #User can be used instead if guardians or other roles are needed.
    #$users = Get-Data @splat -EndpointUri "/users" -Authorization $authorization
    $students = Get-Data @splat -EndpointUri "/students"
    $teachers = Get-Data @splat -EndpointUri "/teachers"

    $availablePersons = [System.Collections.ArrayList]@();
    $availablePersons.AddRange($students);
    $availablePersons.AddRange($teachers);

    $enrollmentsHT = @{};
    $classesHT = @{};
    $academicSessionsHT = @{};
    $orgsHT = @{};
    $coursesHT = @{};

    foreach($user in $availablePersons)
    {
        $enrollmentsHT[$user.sourcedId] = [System.Collections.ArrayList]@();
    }

    foreach($e in $enrollments)
    {
        [void]$enrollmentsHT[$e.user.sourcedId].Add($e);
    }

    foreach($c in $classes)
    {
        $classesHT[$c.sourcedId] = $c;
    }

    foreach($a in $academicSessions)
    {
        $academicSessionsHT[$a.sourcedId] = $a;
    }

    foreach($o in $orgs)
    {
        $orgsHT[$o.sourcedId] = $o;
    }

    foreach($crs in $courses)
    {
        $coursesHT[$crs.sourcedId] = $crs;
    }

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

        foreach($e in $enrollmentsHT[$user.sourcedId])
        {
            try {
                $contract = @{};
                foreach($prop in $e.PSObject.properties)
                {
                    if(@("class","school","user") -contains $prop.Name) { continue; }
                    $contract[$prop.Name] = "$($prop.Value)";
                }

                $c = try { $classesHT[$e.class.sourcedId] } catch { @{} }
                #Class for Enrollment
                $contract['class'] = @{};
                foreach($prop in $c.PSObject.properties)
                {
                    if(@("subjects","course","school","terms","subjectCodes","periods") -contains $prop.Name) { continue; }
                    $contract.class[$prop.Name] = "$($prop.Value)";
                }

                #Academic Sessions for Class
                $contract['terms'] = [System.Collections.ArrayList]@();

                foreach($as in $c.terms)
                {
                    $as = try { $academicSessionsHT[$c.terms.sourcedId] } catch { @() }
                    $term = @{};
                    foreach($prop in $as.PSObject.properties)
                    {
                        if(@("parent") -contains $prop.Name) { continue; }
                        $term[$prop.Name] = "$($prop.Value)";
                    }
                    [void]$contract['terms'].Add($term);
                }          

                #Course for Class
                $contract['course'] = @{};
                $crs = try { $coursesHT[$c.course.sourcedId]  } catch { @{} }
   
                foreach($prop in $crs.PSObject.properties)
                {
                    if(@("org","grades","subjectCodes","schoolYear") -contains $prop.Name) { continue; }
                    $contract.course[$prop.Name] = "$($prop.Value)";
                }

                #School for Enrollment
                $contract['school'] = try { $orgsHT[$e.school.sourcedId]  } catch { @{} }
            
                [void]$person.Contracts.Add($contract);
            } catch {
                Write-Verbose -Verbose "Failed to process contracts for $($person['ExternalId']) - $($e.sourcedId)"
            }
            
        
        }
    
        $person | ConvertTo-Json -Depth 50
    } 
}
catch { throw $_ }