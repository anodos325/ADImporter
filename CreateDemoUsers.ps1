#Credit for original script to Helge Klein https://helgeklein.com.
#Adapted to allow higher numbers of users with the same information set

Set-StrictMode -Version 2

Import-Module ActiveDirectory

# Set the working directory to the script's directory
Push-Location (Split-Path ($MyInvocation.MyCommand.Path))

#
# Global variables
#
# User properties
$ou = "OU=TEST,DC=THEGIBSON,DC=LAN"         # Which OU to create the user in
$groupou = "OU=TESTGROUP,DC=THEGIBSON,DC=LAN"
$initialPassword = "Password1"               # Initial password set for the user
$orgShortName = "THEGIBSON"                         # This is used to build a user's sAMAccountName
$dnsDomain = "THEGIBSON.LAN"                      # Domain is used for e-mail address and UPN
$company = "THEGIBSON co"                           # Used for the user object's company attribute
$departments = (                             # Departments and associated job titles to assign to the users
                  @{"Name" = "Finance & Accounting"; Positions = ("Manager", "Accountant", "Data Entry")},
                  @{"Name" = "Human Resources"; Positions = ("Manager", "Administrator", "Officer", "Coordinator")},
                  @{"Name" = "Sales"; Positions = ("Manager", "Representative", "Consultant")},
                  @{"Name" = "Marketing"; Positions = ("Manager", "Coordinator", "Assistant", "Specialist")},
                  @{"Name" = "Engineering"; Positions = ("Manager", "Engineer", "Scientist")},
                  @{"Name" = "Consulting"; Positions = ("Manager", "Consultant")},
                  @{"Name" = "IT"; Positions = ("Manager", "Engineer", "Technician")},
                  @{"Name" = "Planning"; Positions = ("Manager", "Engineer")},
                  @{"Name" = "Contracts"; Positions = ("Manager", "Coordinator", "Clerk")},
                  @{"Name" = "Purchasing"; Positions = ("Manager", "Coordinator", "Clerk", "Purchaser")}
               )
$phoneCountryCodes = @{"GB" = "+44"}         # Country codes for the countries used in the address file

# Other parameters
$userCount = 5000                           # How many users to create
$locationCount = 1                          # How many different offices locations to use
$employeeNumber = 1

# Files used
$firstNameFile = "Firstnames.txt"            # Format: FirstName
$lastNameFile = "Lastnames.txt"              # Format: LastName
$addressFile = "Addresses.txt"               # Format: City,Street,State,PostalCode,Country
$postalAreaFile = "PostalAreaCode.txt"       # Format: PostalCode,PhoneAreaCode

#
# Read input files
#
$firstNames = Import-CSV $firstNameFile
$lastNames = Import-CSV $lastNameFile
$addresses = Import-CSV $addressFile
$postalAreaCodesTemp = Import-CSV $postalAreaFile

# Convert the postal & phone area code object list into a hash
$postalAreaCodes = @{}
foreach ($row in $postalAreaCodesTemp)
{
   $postalAreaCodes[$row.PostalCode] = $row.PhoneAreaCode
}
$postalAreaCodesTemp = $null

#
# Preparation
#
$securePassword = ConvertTo-SecureString -AsPlainText $initialPassword -Force

# Select the configured number of locations from the address list
$locations = @()
$addressIndexesUsed = @()
for ($i = 0; $i -le $locationCount; $i++)
{
   # Determine a random address
   $addressIndex = -1
   do
   {
      $addressIndex = Get-Random -Minimum 0 -Maximum $addresses.Count
   } while ($addressIndexesUsed -contains $addressIndex)
   
   # Store the address in a location variable
   $street = $addresses[$addressIndex].Street
   $city = $addresses[$addressIndex].City
   $state = $addresses[$addressIndex].State
   $postalCode = $addresses[$addressIndex].PostalCode
   $country = $addresses[$addressIndex].Country
   $locations += @{"Street" = $street; "City" = $city; "State" = $state; "PostalCode" = $postalCode; "Country" = $country}
   
   # Do not use this address again
   $addressIndexesUsed += $addressIndex
}

# Create Groups
1..100 | % { New-ADGroup -Name "Group$_" -SamAccountName "Group$_" -GroupCategory Security -GroupScope Global -Path $groupou}
$grouplist = Get-ADGroup -Filter * -SearchBase $groupou
#
# Create the users
#

#
# Randomly determine this user's properties
#
   
# Sex & name
for ($i = 0; $i -lt $userCount; $i++)
{
    $Fname = $firstNames[$(Get-Random -Minimum 0 -Maximum $firstNames.Count)].Firstname
    $Lname = $lastNames[$(Get-Random -Minimum 0 -Maximum $lastNames.Count)].Lastname

    $displayName = $Fname + " " + $Lname

   # Address
   $locationIndex = Get-Random -Minimum 0 -Maximum $locations.Count
   $street = $locations[$locationIndex].Street
   $city = $locations[$locationIndex].City
   $state = $locations[$locationIndex].State
   $postalCode = $locations[$locationIndex].PostalCode
   $country = $locations[$locationIndex].Country
   
   # Department & title
   $departmentIndex = Get-Random -Minimum 0 -Maximum $departments.Count
   $department = $departments[$departmentIndex].Name
   $title = $departments[$departmentIndex].Positions[$(Get-Random -Minimum 0 -Maximum $departments[$departmentIndex].Positions.Count)]

   # Phone number
   if (-not $phoneCountryCodes.ContainsKey($country))
   {
      "ERROR: No country code found for $country"
      continue
   }
   if (-not $postalAreaCodes.ContainsKey($postalCode))
   {
      "ERROR: No country code found for $country"
      continue
   }
   $officePhone = $phoneCountryCodes[$country] + "-" + $postalAreaCodes[$postalCode].Substring(1) + "-" + (Get-Random -Minimum 100000 -Maximum 1000000)
   
   # Build the sAMAccountName: $orgShortName + employee number
   $sAMAccountName = $Fname + $Lname
   $userExists = $false
   Try   { $userExists = Get-ADUser -LDAPFilter "(sAMAccountName=$sAMAccountName)" }
   Catch { }
   if ($userExists)
   {
      $i=$i-1
      if ($i -lt 0)
      {$i=0}
      continue
   }

   #
   # Create the user account
   #
      New-ADUser -SamAccountName $sAMAccountName -Name $displayName -Path $ou -AccountPassword $securePassword -Enabled $true -GivenName $Fname -Surname $Lname -DisplayName $displayName -EmailAddress "$Fname.$Lname@$dnsDomain" -StreetAddress $street -City $city -PostalCode $postalCode -State $state -Country $country -UserPrincipalName "$sAMAccountName@$dnsDomain" -Company $company -Department $department -EmployeeNumber $employeeNumber -Title $title -OfficePhone $officePhone

   "Created user #" + ($i+1) + ", $displayName, $sAMAccountName, $title, $department, $street, $city"
   $i = $i+1
   $employeeNumber = $employeeNumber+1

   $groupcount = Get-Random -Minimum 5 -Maximum 100
   $groupsToAdd = Get-Random -InputObject $grouplist -Count $groupcount
   foreach ($gr in $groupsToAdd)
   {
       "Adding $sAMAccountName to the following group: $gr"
       Add-ADGroupMember -Identity $gr $sAMAccountName
   }

      if ($i -ge $userCount) 
   {
       "Script Complete. Exiting"
       exit
   }
}
