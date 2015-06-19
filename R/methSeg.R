# segmentation functions 

#' Segment methylation or differential methylation profile
#' 
#' The function uses a segmentation algorithm (\code{\link[fastseg]{fastseg}}) 
#' to segment the methylation profiles. Following that, it uses
#' gaussian mixture modelling to cluster the segments into k components. This process
#' uses mean methylation value of each segment in the modeling phase. Each
#' component ideally indicates quantitative classification of segments, such
#' as high or low methylated regions.
#' 
#' @param obj \code{\link[GenomicRanges]{GRanges}}, \code{\link{methylDiff}} or 
#'            \code{\link{methylBase}}. If the object is a 
#'            \code{\link[GenomicRanges]{GRanges}}
#'             it should have one meta column with methylation scores
#' @param diagnostic.plot if TRUE a diagnostic plot is plotted. The plot shows
#'        methylation and length statistics per segment group. In addition, it 
#'        shows diagnostics from mixture modeling: the density function estimated 
#'        and BIC criterion used to decide the optimum number of components
#'        in mixture modeling.
#' @param obj \code{\link[GenomicRanges]{GRanges}}, 
#'       \code{\link[methylKit]{methylRaw}} or \code{\link[methylKit]{methylDiff}} 
#'        object to be segmented
#' @param ... arguments to \code{\link[fastseg]{fastseg}} function in fastseg 
#' package, or to \code{\link[mclust]{densityMclust}}
#'        in Mclust package, could be used to fine tune the segmentation algorithm.
#'        E.g. Increasing "alpha" will give more segments. 
#'        Increasing "cyberWeight" will give also more segments."maxInt" controls
#'        the segment extension around a breakpoint. "minSeg" controls the minimum
#'        segment length. "G" argument
#'        denotes number of components used in BIC selection in mixture modeling.
#'        For more details see fastseg and Mclust documentation.    
#'        
#'               
#' @return A \code{\link[GenomicRanges]{GRanges}} object with segment 
#'         classification and information. 
#'        'seg.mean' column shows the mean methylation per segment.
#'        'seg.group' column shows the segment groups obtained by mixture modeling
#'               
#' @details      
#'        To be sure that the algorithm will work on your data, 
#'        the object should have at least 5000
#' @examples 
#' 
#' \donttest{
#'  download.file("https://dl.dropboxusercontent.com/content_link/eOYpRiv48Dg97bOtLiO7Qf9fsLxVN2IufbLJzD8Gy2tpXLqH0rMNsCAu0TZeuorV?dl=1",destfile="H1.chr21.chr22.rds",method="curl")
#' 
#'  mbw=readRDS("H1.chr21.chr22.rds")
#' 
#'  # it finds the optimal number of componets as 6
#'  res=methSeg(mbw,diagnostic.plot=TRUE,maxInt=100,minSeg=10)
#' 
#'  # however the BIC stabilizes after 4, we can also try 4 componets
#'  res=methSeg(mbw,diagnostic.plot=TRUE,maxInt=100,minSeg=10,G=1:4)
#' 
#'  # get segments to BED file
#'  methSeg2bed(res,filename="H1.chr21.chr22.trial.seg.bed")
#' }
#' 
#' @author Altuna Akalin, contributions by Arsene Wabo
#' 
#' @seealso \code{\link{methSeg2bed}}
#' 
#' @export
#' @docType methods
#' @rdname methSeg       
methSeg<-function(obj, diagnostic.plot=TRUE, ...){
  
  dots <- list(...)  
  
  if(class(obj)=="methylRaw"){
    obj= as(obj,"GRanges")
    mcols(obj)=100*obj$numCs/obj$coverage
  }else if(class(obj)=="methylDiff"){
    obj = as(obj,"GRanges")
    obj = sort(obj[,-1])
  }else if (class(obj) != "GRanges"){
    stop("only methylRaw, methylDiff or GRanges objects can be used in this function")
  }
  
  # match argument names to fastseg arguments
  args.fastseg=dots[names(dots) %in% names(formals(fastseg)[-1] ) ]  
  
  # match argument names to Mclust
  args.Mclust=dots[names(dots) %in% names(formals(Mclust)[-1])  ]
  
  args.fastseg[["x"]]=obj
  
  # do the segmentation
  #seg.res=fastseg(obj)
  seg.res <- do.call("fastseg", args.fastseg,envir = parent.frame())
  
  # decide on number of components/groups
  args.Mclust[["score.gr"]]=seg.res
  args.Mclust[["diagnostic.plot"]]=diagnostic.plot
  dens=do.call("densityFind", args.Mclust  )
  
  # add components/group ids 
  mcols(seg.res)$seg.group=as.character(dens$classification)
  
  seg.res
}

# not needed
.methSeg<-function(score.gr,score.cols=NULL,...){
  #require(fastseg)
  
  
  if(!is.null(score.cols)){
    values(score.gr)=score.gr[,score.cols]
  }
  
  seg.res <- fastseg(score.gr,...)
  
}

# finds segment groups using mixture modeling
densityFind<-function(score.gr,diagnostic.plot=T,...){
  dens = densityMclust(score.gr$seg.mean,... )
  
  if(diagnostic.plot){
    diagPlot(dens,score.gr)
  }
  dens
}


# diagnostic plot, useful for parameter trials
diagPlot<-function(dens,score.gr){
  
  scores=score.gr$seg.mean
  par(mfrow=c(2,3))
  boxplot(
    lapply(1:dens$G,function(x) scores[dens$classification==x] ),
    horizontal=T,main="methylation per group",xlab="methylation")
  
  boxplot(
    lapply(1:dens$G,function(x) log10(width(score.gr)[dens$classification==x]) ),
    horizontal=T,main="segment length per group",
    xlab="log10(length) in bp ",outline=FALSE)
  
  
  #lapply(1:dens$G,function(x) mean(width(score.gr)[dens$classification==x] ))
  
  barplot(table(dens$classification),xlab="segment groups",
          ylab="number of segments")
  plot(dens,what="density")  
  plot(dens,what="BIC")  
  
  par(mfrow=c(1,1))
  
}

#' Export segments to BED files
#' 
#' The segments are color coded based on their score (methylation or differential
#' methylation value). They are named by segment group (components in mixture modeling)
#' and the score in the BED file is obtained from 'seg.mean' column of segments
#' object.
#' 
#' @param segments \code{\link[GenomicRanges]{GRanges}} object with segment 
#' classification and information. This should be the result of 
#' \code{\link{methSeg}} function
#' @param trackLine UCSC browser trackline
#' @param filename name of the output data
#' @param colramp color scale to be used in the BED display
#' defaults to gray,green, darkgreen scale.
#' 
#' @return A BED files with the segmented data
#' which can be visualized in the UCSC browser 
#' 
#' @seealso \code{\link{methSeg}}
#' 
#' @export
#' @docType methods
#' @rdname methSeg2bed
methSeg2bed<-function(segments,
                      trackLine="track name='meth segments' description='meth segments' itemRgb=On",
                      filename="data/H1.chr21.chr22.trial.seg.bed",
                      colramp=colorRamp(c("gray","green", "darkgreen"))
                        ){
  #require(rtracklayer)
  ramp <- colramp
  mcols(segments)$name=as.character(segments$seg.group)
  
  #scores=(segments$seg.mean-min(segments$seg.mean))/(max(segments$seg.mean))-(min(segments$seg.mean))
  scores=(segments$seg.mean-min(segments$seg.mean))/(max(segments$seg.mean)-min(segments$seg.mean))
  
  mcols(segments)$itemRgb= rgb(ramp(scores), max = 255) 
  #strand(segments)="."
  score(segments)=segments$seg.mean
  
  if(is.null(trackLine)){
    
    export.bed(segments,filename)
  }else{
    export.bed(segments,filename,
               trackLine=as(trackLine, "BasicTrackLine"))
  }
}