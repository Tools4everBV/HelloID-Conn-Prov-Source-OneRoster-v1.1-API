[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12
Write-Information "Processing Persons"
#region Configuration
if($null -eq $configuration){
    $configuration = '' # Get JSON from HelloID
    $InformationPreference = 'continue'
}

$config = ConvertFrom-Json $configuration
#endregion Configuration

#region Support Functions
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
        $requestUri = "{0}{1}" -f $BaseURI, $TokenURI
        
        $pair       = "{0}:{1}" -f $ClientKey,$ClientSecret
        $bytes      = [System.Text.Encoding]::ASCII.GetBytes($pair)
        $bear_token = [System.Convert]::ToBase64String($bytes)
        $headers    = @{   
            Authorization = "Basic {0}" -f $bear_token
            Accept  = "application/json"
        }
        
        $parameters = @{grant_type="client_credentials"}
        
        Write-Information ("POST {0}" -f $requestUri)
        $splat = @{
            Method  = 'Post'
            URI     = $requestUri
            Body    = $parameters 
            Headers = $headers 
            Verbose = $false
        }
        $response = Invoke-RestMethod @splat
        #Write-Information $response
        $accessToken       = $response.access_token
    
        #Add the authorization header to the request
        $authorization = @{
            Authorization  = "Bearer {0}" -f $accesstoken
            'Content-Type' = "application/json"
            Accept         = "application/json"
        }
        $authorization
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
    Begin
    {
        $offset        = 0
        $requestUri    = "{0}{1}{2}" -f $BaseURI,$VersionUri,$EndPointUri
        $propertyArray = $EndpointURI -replace '/','' -replace '^students|teachers$','users'
        
        $results       = [System.Collections.Generic.List[object]]::new()
    }
    
    Process 
    {
        do
        {
            $parameters = @{
                limit  = $PageSize
                offset = $offset
            }
            Write-Information ("GET {0} ({1})" -f $requestUri, $offset)

            $splat = @{
                Method  = 'GET'
                Uri     = $requestUri 
                Body    = $parameters 
                Headers = $Authorization 
                Verbose = $false
            }
            
            try {
                $response = Invoke-RestMethod @splat
            }
            catch {
                Write-Information ("  Retrying RestMethod.  Error:  $_" -f $_)
                Start-Delay -seconds 5
                $response = Invoke-RestMethod @splat
            }

            $results.AddRange($response.$propertyArray)
            
            $offset = $offset + $response.$propertyArray.count
        } while ($response.$propertyArray.count -eq $PageSize)
    }
    
    End
    {
        return $results
    }
}

function Group-ObjectHashtable
{
    param(
        [string[]] $Property
    )

    begin
    {   # create an empty hashtable
        $hashtable = @{}
    }

    process
    {   # create a key based on the submitted properties, and turn it into a string
        $key = $(foreach($prop in $Property) { $_.$prop }) -join ','
        
        # check to see if the key is present already
        if ($hashtable.ContainsKey($key) -eq $false)
        {   # add an empty list
            $hashtable[$key] = [Collections.Generic.List[psobject]]::new()
        }

        # add element to appropriate array list:
        $hashtable[$key].Add($_)
    }

    end
    {   # return the entire hashtable:
        $hashtable
    }
}

#endregion Support Functions

#region Get Data
$splat = @{
    BaseURI = $config.BaseURI
    VersionUri = $config.VersionUri
    TokenUri = $config.TokenUri
    ClientKey = $config.ClientKey
    ClientSecret = $config.ClientSecret
    PageSize = $config.PageSize
}
$mc = Measure-Command {
    $splat['Authorization'] = Get-AuthToken @splat
    $orgs               = Get-Data @splat -EndpointUri "/orgs" 
    $orgs_ht            = $orgs | Group-ObjectHashtable 'sourcedId'
        $orgs_empty = @{}
        $orgs[0].PSObject.Properties.ForEach({$orgs_empty[$_.name -Replace '\W','_'] = ''})
    $academicSessions   = Get-Data @splat -EndpointUri "/academicSessions"
    $academicSessions_ht= $academicSessions | Group-ObjectHashtable 'sourcedId'

    $enrollments        = Get-Data @splat -EndpointUri "/enrollments"
        $enrollments_ht = $enrollments | Group-Object -Property @{e={$_.user.sourcedID}} -AsString -AsHashTable
    $classes            = Get-Data @splat -EndpointUri "/classes"
        $classes_ht     = $classes | Group-ObjectHashtable 'sourcedId'
    $courses            = Get-Data @splat -EndpointUri "/courses"
        $courses_ht     = $courses | Group-ObjectHashtable 'sourcedId'  

    #User can be used instead if guardians or other roles are needed.
    #$users             = Get-Data @config -EndpointUri "/users"
    $students           = Get-Data @splat -EndpointUri "/students"
    $teachers           = Get-Data @splat -EndpointUri "/teachers"

    $availablePersons = [System.Collections.Generic.List[object]]::new()
    $availablePersons.AddRange($students)
    $availablePersons.AddRange($teachers)

    # Other EndPoints
    $demographics           = Get-Data @splat -EndpointUri "/demographics"
}
Write-Information "Data Pulled in $($mc.days):$($mc.hours):$($mc.minutes):$($mc.seconds).$($mc.milliseconds)"
#endregion Get Data

#region Prepare Return Data
$mc = Measure-Command {
    $return = [System.Collections.Generic.List[psobject]]::new()
    $_i = 0
    $now = Get-Date
    foreach($user in $availablePersons)
    {  
        $person = @{}
        $person['ExternalId']   = '{0}' -f $user.sourcedId
        $person['DisplayName']  = '{0} {1} ({2})' -f $user.givenName, $user.familyName, $user.sourcedId
        if(($_i++ % 500) -eq 0)
        {
            Write-Information ('Processing Return: ({0}/{1}) {2:n1} s...' -f $_i,$availablePersons.count,((Get-Date) - $now).TotalSeconds)
        }
    
        $_skipfields = @("orgs","agents","grades")
        foreach($prop in ($user.PSObject.properties)) #.Where({$_skipfields -notcontains $_.Name })))
        {
            if($_skipfields -notcontains $prop.Name)
            {
                $person[$prop.Name -replace '\W','_'] = $prop.Value
            }
        }
        # Process student Orgs.  Exclude 'District' org.
        $person['orgs'] = [System.Collections.Generic.List[pscustomobject]]::new()
        foreach($_org in $user.orgs)
        {
            $school = @{}
            $org = $orgs_ht[$_org.sourcedId.ToString()][0]
            if($org.type -ne 'district')
            {
                $_skipfields = @("parent")
                foreach($prop in ($org.PSObject.properties))
                {
                    if($_skipfields -notcontains $prop.Name)
                    {
                        $school[$prop.Name -replace '\W','_'] = $prop.Value
                    }
                }
                $person['orgs'].add($school)
            }
        }

        # Grade - Convert from Array to just a string.
        $person['grades'] = try{$user.grades[0]}catch{''}

        # Not including Agents.  Only needed if mapping Parent/Guardian data.
        #$person['agents'] = $user.agents.sourcedId

        # Add Contracts
        $person['Contracts'] = [System.Collections.Generic.List[psobject]]::new()
    
        # Add Class Enrollments
        foreach($e in $enrollments_ht[$user.sourcedId.ToString()])
        {
            $contract = @{
                externalID = $e.sourcedId
                Class = @{}
            }
            # Process Enrollment Fields
            $_skipfields = @("class","school","user")
            foreach($prop in ($e.PSObject.properties)) # | ? {$_skipfields -notcontains $_.Name}))
            {
                if($_skipfields -notcontains $prop.Name)
                {
                    $contract[$prop.Name -replace '\W','_'] = $prop.Value
                }
            }

            #Class for Enrollment
            $c = $classes_ht[$e.class.sourcedId.ToString()][0]
            $_skipfields = @("course","school","terms")  #"periods","subjects","subjectCodes",
            foreach($prop in ($c.PSObject.properties))# | ? {$_skipfields -notcontains $_.Name}))
            {
                if($_skipfields -notcontains $prop.Name)
                {
                    $contract.class[$prop.Name -replace '\W','_'] = $prop.Value
                }
            }
            
            # Sequence used for Priority Logic.  Priority:  HomeRoom, scheduled, everything else
            switch ($c.classType)
            {
                'homeroom'  {$contract['Sequence'] = 1}
                'scheduled' {$contract['Sequence'] = 2}
                default     {$contract['Sequence'] = 3}
            }
            
            #Academic Sessions/Terms for Class  (Not including Terms due to excessive memory use in HelloID error)
            #$contract['terms'] = [System.Collections.Generic.List[psobject]]::new()   
            foreach($_term in $c.terms)
            {
                $term = @{}
                $as = $academicSessions_ht[$_term.sourcedId.ToString()][0]
                $_skipfields = @("children")
                foreach($prop in ($as.PSObject.properties)) # | ? {$_skipfields -notcontains $_.Name}))
                {
                    if($_skipfields -notcontains $prop.Name)
                    {
                        $term[$prop.Name -replace '\W','_'] = $prop.Value
                    }
                }
                #$contract['terms'].Add($term)
                # Update Earliest and Latest Term Start/End Dates for Class.
                $contract['startDate'] = $(if(!$contract['startDate'] -OR $contract['startDate'] -gt $term.startDate){$term.startDate}else{$contract['startDate']})
                $contract['endDate'] = $(if(!$contract['endDate'] -OR $contract['endDate'] -lt $term.endDate){$term.endDate}else{$contract['endDate']})
            }
            #Course for Class
            $contract['course'] = @{}
            $crs = $courses_ht[$c.course.sourcedId.ToString()][0]
            $_skipfields = @("org","subjectCodes","subjects")
            foreach($prop in ($crs.PSObject.properties))  # | ? {$_skipfields -notcontains $_.Name}))
            {
                if($_skipfields -notcontains $prop.Name)
                {
                    $contract.course[$prop.Name -replace '\W','_'] = $prop.Value
                }
            }

            #School for Enrollment
            $contract['school'] = @{}
            $sch = $orgs_ht[$c.school.sourcedId.ToString()][0]
            $_skipfields = @("parent")
            foreach($prop in ($sch.PSObject.properties)) # | ? {$_skipfields -notcontains $_.Name}))
            {
                if($_skipfields -notcontains $prop.Name)
                {
                    $contract.school[$prop.Name -replace '\W','_'] = $prop.Value
                }
            }

            # Add Location Enrichment Data Here (if needed)

            $person.Contracts.Add($contract)
        }
        $return.add($person)
    }
    
}
Write-Information "Return Processed in $($mc.days):$($mc.hours):$($mc.minutes):$($mc.seconds).$($mc.milliseconds)"
#endregion Prepare Return Data

#region Return Data to HelloID
$return | %{ Write-Output ($_ | ConvertTo-Json -Depth 10) }
Write-Information "Finished Processing Persons"
#endregion Return Data to HelloID