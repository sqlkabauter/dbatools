function Set-DbaJobOwner {
	<#
		.SYNOPSIS
			Sets SQL Agent job owners with a desired login if jobs do not match that owner.

		.DESCRIPTION
			This function will alter SQL Agent Job ownership to match a specified login if their
			current owner does not match the target login. By default, the target login will
			be 'sa', but the fuction will allow the user to specify a different login for
			ownership. The user can also apply this to all jobs or only to a select list
			of jobs (passed as either a comma separated list or a string array).

			Best practice reference: http://sqlmag.com/blog/sql-server-tip-assign-ownership-jobs-sysadmin-account

		.NOTES
			Tags: Agent, Job
			Original Author: Michael Fal (@Mike_Fal), http://mikefal.net

			Website: https://dbatools.io
			Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
			License: GNU GPL v3 https://opensource.org/licenses/GPL-3.0

		.PARAMETER SqlInstance
			SQLServer name or SMO object representing the SQL Server to connect to. This can be a
			collection and recieve pipeline input

		.PARAMETER SqlCredential
			PSCredential object to connect under. If not specified, currend Windows login will be used.

		.PARAMETER Job
			The job(s) to process - this list is auto populated from the server. If unspecified, all jobs will be processed.

		.PARAMETER ExcludeJob
			The job(s) to exclude - this list is auto populated from the server.

		.PARAMETER Login
			Specific login that you wish to check for ownership - this list is auto populated from the server. This defaults to 'sa' or the sysadmin name if sa was renamed.

		.PARAMETER WhatIf
			Shows what would happen if the command were to run. No actions are actually performed.

		.PARAMETER Confirm
			Prompts you for confirmation before executing any changing operations within the command.

		.PARAMETER Silent
			Use this switch to disable any kind of verbose messages

		.LINK
			https://dbatools.io/Set-DbaJobOwner

		.EXAMPLE
			Set-DbaJobOwner -SqlInstance localhost

			Sets SQL Agent Job owner to sa on all jobs where the owner does not match sa.

		.EXAMPLE
			Set-DbaJobOwner -SqlInstance localhost -Login DOMAIN\account

			Sets SQL Agent Job owner to sa on all jobs where the owner does not match 'DOMAIN\account'. Note
			that Login must be a valid security principal that exists on the target server.

		.EXAMPLE
			Set-DbaJobOwner -SqlInstance localhost -Job job1, job2

			Sets SQL Agent Job owner to 'sa' on the job1 and job2 jobs if their current owner does not match 'sa'.

		.EXAMPLE
			'sqlserver','sql2016' | Set-DbaJobOwner

			Sets SQL Agent Job owner to sa on all jobs where the owner does not match sa on both sqlserver and sql2016.
	#>
	[CmdletBinding(SupportsShouldProcess = $true)]
	param (
		[parameter(Mandatory = $true, ValueFromPipeline = $true)]
		[Alias("ServerInstance", "SqlServer")]
		[DbaInstanceParameter[]]$SqlInstance,
		[PSCredential][System.Management.Automation.CredentialAttribute()]
		$SqlCredential,
		[object[]]$Job,
		[object[]]$ExcludeJob,
		[Alias("TargetLogin")]
		[object]$Login,
		[switch]$Silent
	)

	process {
		foreach ($servername in $SqlInstance) {
			#connect to the instance
			Write-Message -Level Verbose -Message "Connecting to $servername"
			$server = Connect-SqlInstance $servername -SqlCredential $SqlCredential

			# dynamic sa name for orgs who have changed their sa name
			if (!$Login) {
				$Login = ($server.logins | Where-Object { $_.id -eq 1 }).Name
			}

			#Validate login
			if (($server.Logins.Name) -notcontains $Login) {
				if ($SqlInstance.count -eq 1) {
					Stop-Function -Message "Invalid login: $Login"
				}
				else {
					Write-Message -Level Warning -Message "$Login is not a valid login on $servername. Moving on."
					Continue
				}
			}

			if ($server.logins[$Login].LoginType -eq 'WindowsGroup') {
				Stop-Function -Message "$Login is a Windows Group and can not be a job owner."
			}

			#Get database list. If value for -Job is passed, massage to make it a string array.
			#Otherwise, use all jobs on the instance where owner not equal to -TargetLogin
			Write-Message -Level Verbose -Message "Gathering jobs to update"

			if ($Job) {
				$jobcollection = $server.JobServer.Jobs | Where-Object { $_.OwnerLoginName -ne $Login -and $Job -contains $_.Name }
			}
			else {
				$jobcollection = $server.JobServer.Jobs | Where-Object { $_.OwnerLoginName -ne $Login }
			}

			if ($ExcludeJob) {
				$jobcollection = $jobcollection | Where-Object { $ExcludeJob -notcontains $_.Name }
			}

			Write-Message -Level Verbose -Message "Updating $($jobcollection.Count) job(s)."
			foreach ($j in $jobcollection) {
				$jobname = $j.name

				If ($PSCmdlet.ShouldProcess($servername, "Setting job owner for $jobname to $Login")) {
					try {
						Write-Message -Level Verbose -Message "Setting job owner for $jobname to $Login on $servername"
						#Set job owner to $TargetLogin (default 'sa')
						$j.OwnerLoginName = $Login
						$j.Alter()
					}
					catch {
						# write-exception writes the full exception to file
						Stop-Function -Message "Issue setting job owner on $jobName" -Target $jobName -InnerErrorRecord $_ -Category InvalidOperation
					}
				}
			}
		}
	}
}
