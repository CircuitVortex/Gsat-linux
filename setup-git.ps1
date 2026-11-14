# One-shot git setup for this repo. Prompts for identity + remote, then pushes.
Set-Location "C:\Users\Xerxes Robb Arsolon\Desktop\Reverse"

$name  = Read-Host "Your name"
$email = Read-Host "GitHub email"
$url   = Read-Host "Repo URL (https://github.com/USER/REPO.git)"

git config user.name  $name
git config user.email $email
git commit --amend --reset-author --no-edit

git remote remove origin 2>$null
git remote add origin $url

git push -u origin main

if ($LASTEXITCODE -eq 0) { "done - check the Actions tab" } else { "push failed - see message above" }
