$specs = @(
 @('blank-notebooks','A notebook.jpg','notebook1'),
 @('blank-notebooks','New text notebook (Unsplash).jpg','notebook2'),
 @('gel-pens','Stick-Pens Colored 30866-480x360 (4904342193).jpg','pens1'),
 @('gel-pens','Sakura Gelly Roll 08 Pens.jpg','pens2'),
 @('highlighters','CreativeTools.se - PackshotCreator - Överstrykningspennor 01 (5078496726).jpg','highlighters1'),
 @('highlighters','Textmarker mit verschiedenen Farben.JPG','highlighters2'),
 @('mechanical-pencils','Mechpencil05.jpg','pencil1'),
 @('mechanical-pencils','Mechanical pencil.jpg','pencil2'),
 @('post-it-notes','Post it notes.jpg','sticky1'),
 @('post-it-notes','3MPostItNote2.jpg','sticky2'),
 @('washi-tapes','Gamme Washi Tape.jpg','tape1'),
 @('washi-tapes','Slim Washi Tape.jpg','tape2'),
 @('pen-and-pencil-cases','Eastpak astuccio gray.jpg','case1'),
 @('pen-and-pencil-cases','Pencil Case - Closed (37896716781).jpg','case2'),
 @('graph-paper','Graph paper notepad (4562203394).jpg','grid1'),
 @('graph-paper','Spiralblock-aufgeschlagen.jpg','grid2'),
 @('erasers','Office-pink-erasers.jpg','erasers1'),
 @('erasers','Erasers 2023.jpg','erasers2')
)
$records=@()
foreach($spec in $specs) {
 $data=Get-Content ('myapp/assets/images/research/'+$spec[0]+'.json') -Raw|ConvertFrom-Json
 $page=$data.query.pages.PSObject.Properties.Value|Where-Object {$_.title -eq ('File:'+$spec[1])}
 $info=$page.imageinfo[0]
 $url=if($info.thumburl){$info.thumburl}else{$info.url}
 try { Invoke-WebRequest -Uri $url -OutFile ('myapp/assets/images/research/'+$spec[2]+'.jpg') } catch { Write-Output ($spec[2]+': '+$_.Exception.Message) }
 $records+=@{key=$spec[2];title=$page.title;info=$info}
 Start-Sleep -Milliseconds 800
}
$records|ConvertTo-Json -Depth 20|Set-Content myapp/assets/images/research/candidates.json
