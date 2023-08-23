$fqdn = [System.Net.Dns]::GetHostByName($env:COMPUTERNAME).HostName
$cert = New-SelfSignedCertificate -Subject "CN=$fqdn" -DnsName $fqdn -CertStoreLocation "cert:\LocalMachine\My" -KeySpec KeyExchange -KeyUsage KeyEncipherment, DataEncipherment -TextExtension @("2.5.29.37={text}1.3.6.1.5.5.7.3.1") -NotAfter (Get-Date).AddYears(3)
$store = New-Object System.Security.Cryptography.X509Certificates.X509Store -ArgumentList "Root", "LocalMachine"
$store.Open("ReadWrite")
$store.Add($cert)
$store.Close()
