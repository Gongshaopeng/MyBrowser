//
//  BNM3U8AnalysisService.m
//  m3u8Demo
//
//  Created by Bennie on 6/14/19.
//  Copyright © 2019 Bennie. All rights reserved.
//

#import "BNM3U8AnalysisService.h"
#import "NSString+m3u8.h"
#import "BNM3U8PlistInfo.h"
#import "BNM3U8PlistInfo.h"
#import "BNTool.h"
#import "BNFileManager.h"

/*解析m3u8 和组装m3u8*/

NSString *fullPerfixPath(NSString *rootPath,NSString *url){
    return  [rootPath stringByAppendingPathComponent:[BNTool uuidWithUrl:url]];
}

@implementation BNM3U8AnalysisService
+ (void)analysisWithURL:(NSString *)urlStr rootPath:(NSString *)rootPath resultBlock:(BNM3U8AnalysisServiceResultBlock)resultBlock
{
    NSLog(@"analysis start");
    
    NSString *oriM3u8Path = [fullPerfixPath(rootPath,urlStr) stringByAppendingPathComponent:@"ori.m3u8"];
    NSString *oriM3u8String = [NSString stringWithContentsOfFile:oriM3u8Path encoding:0 error:nil];
    
    //    NSString *oriM3u8String = [NSString stringWithContentsOfFile:[[ZBLM3u8Setting fullCommonDirPrefixWithUrl:urlStr] stringByAppendingPathComponent:[ZBLM3u8Setting oriM3u8InfoFileName]] encoding:0 error:nil];
   
    __block BOOL happenException = NO;
    if (oriM3u8String.length) {
        NSLog(@"use local oriM3u8Info");
        @try {
            [BNM3U8AnalysisService analysisWithOriUrlString:urlStr m3u8String:oriM3u8String rootPath:rootPath resultBlock:resultBlock];
        } @catch (NSException *exception) {
            happenException = YES;
            [[BNFileManager shareInstance]removeFileWithPath:oriM3u8Path];
            resultBlock([[NSError alloc]initWithDomain:@"原始m3u8文本文件解析错误" code:NSURLErrorUnknown userInfo:@{@"info":exception.reason}],nil);
        } @finally {
            
        }
        if (!happenException) {
            return;
        }
    }
    ///由于任务已经是异步发起，可以直接使用 initWithContentsOfURL 获取文本数据
    happenException = NO;
    NSString *m3u8Str = nil;
    @try {
        NSError *error = nil;
        m3u8Str = [[NSString alloc] initWithContentsOfURL:[NSURL URLWithString:urlStr] usedEncoding:0 error:&error];
        
        if (error)
        {
            resultBlock(error,nil);
            return ;
        }
        //m3u8下载地址解析例子：
        if([m3u8Str containsString:@"EXT-X-STREAM-INF"]){
            urlStr = [BNTool setParsingWithM3u8Url:urlStr m3u8Str:m3u8Str];
            m3u8Str = [[NSString alloc] initWithContentsOfURL:[NSURL URLWithString:urlStr] usedEncoding:0 error:&error];
        }
        if (m3u8Str.length == 0)
        {
            resultBlock([[NSError alloc]initWithDomain:@"原始m3u8文件内容为空" code:NSURLErrorBadServerResponse userInfo:nil],nil);
            return;
        }
       
        [BNM3U8AnalysisService analysisWithOriUrlString:urlStr m3u8String:m3u8Str rootPath:rootPath resultBlock:resultBlock];
    } @catch (NSException *exception) {
        happenException = YES;
        resultBlock([[NSError alloc]initWithDomain:@"原始m3u8文本文件解析错误" code:NSURLErrorUnknown userInfo:@{@"info":exception.reason}],nil);
    } @finally {}
    
    if (!happenException) {
        /// save dst m3u8 info file
        NSString *dstM3u8Path = [fullPerfixPath(rootPath,urlStr) stringByAppendingPathComponent:@"local.m3u8"];
        [[BNFileManager shareInstance]saveDate:[m3u8Str dataUsingEncoding:NSUTF8StringEncoding] ToFile:dstM3u8Path completaionHandler:nil];
    }
}

+ (void)analysisWithOriUrlString:(NSString*)OriUrlString m3u8String:(NSString*)m3u8String rootPath:(NSString *)rootPath resultBlock:(BNM3U8AnalysisServiceResultBlock)resultBlock
{
    /*
     "https://bitmovin-a.akamaihd.net/content/playhouse-vr/m3u8s/105560_video_360_1000000.m3u8"
     https://bitmovin-a.akamaihd.net/content/playhouse-vr/
     */
    /*如果是相对路径 需要特殊处理*/
    
    if([m3u8String containsString:@"../"])
    {
        NSRange r;
        NSString *a = OriUrlString;
        for (int i = 0; i < 2; i ++) {
            r = [a rangeOfString:@"/" options:NSBackwardsSearch];
            a = [a substringToIndex:r.location];
        }
        a = [a stringByAppendingString:@"/"];
        m3u8String = [m3u8String stringByReplacingOccurrencesOfString:@"../" withString:a];
    }
    BNM3U8PlistInfo *info = [BNM3U8PlistInfo new];
    info.version = [[m3u8String subStringFrom:@"#EXT-X-VERSION:" to:@"#"] removeSpaceAndNewline];
    info.targetduration = [[m3u8String subStringFrom:@"#EXT-X-TARGETDURATION:" to:@"#"] removeSpaceAndNewline];
    info.mediaSequence = [[m3u8String subStringFrom:@"#EXT-X-MEDIA-SEQUENCE:" to:@"#"] removeSpaceAndNewline];
    
    info.keyMethod = [m3u8String subStringFrom:@"#EXT-X-KEY:METHOD=" to:@","];
    info.keyUri = [m3u8String subStringFrom:@"URI=\"" to:@"\""];
    info.keyIv = [[m3u8String subStringFrom:@"IV=" to:@"#"] removeSpaceAndNewline];
    
    NSMutableArray *fileInfos = @[].mutableCopy;
    if (info.keyUri.length > 0) {
        ///加入到 fileInfos
        BNM3U8fileInfo *fileInfo = [BNM3U8fileInfo new];
        fileInfo.oriUrlString = info.keyUri;
        fileInfo.index = - 1;
        /* /md5(url)/keyName*/
        fileInfo.relativeUrl =  [NSString stringWithFormat:@"/%@/key",[BNTool uuidWithUrl:OriUrlString]];
        [fileInfos addObject:fileInfo];
        fileInfo.diskPath =  [NSString stringWithFormat:@"%@%@",rootPath,fileInfo.relativeUrl];
        
    }
    NSRange tsRange = [m3u8String rangeOfString:@"#EXTINF:"];
    if (tsRange.location == NSNotFound) {
        resultBlock([[NSError alloc]initWithDomain:@"没有找到.ts文件信息" code:NSURLErrorUnknown userInfo:@{@"info":@"none downloadUrl for .ts file"}],nil);
        
        return;
    }
   
    NSInteger index = 0;
    m3u8String = [m3u8String substringFromIndex:tsRange.location];
    while (tsRange.location != NSNotFound) {
        @autoreleasepool {
            BNM3U8fileInfo *fileInfo = [BNM3U8fileInfo new];
            fileInfo.duration = [m3u8String subStringFrom:@"#EXTINF:" to:@","];
            m3u8String = [m3u8String subStringForm:@"," offset:1];
            fileInfo.oriUrlString = [[m3u8String subStringTo:@"#"] removeSpaceAndNewline];
            //下载 url 补全
            fileInfo.oriUrlString = [BNTool newisHttpOrHttps:fileInfo.oriUrlString orUrl:OriUrlString];
            
            NSRange exRange = [m3u8String rangeOfString:@"#EX"];
            NSRange discontinuityRange = [m3u8String rangeOfString:@"#EXT-X-DISCONTINUITY"];
            if (exRange.location == discontinuityRange.location) {
                fileInfo.hasDiscontiunity = YES;
            }
            fileInfo.index = index ++;
            /* /md5(url)/fileName*/
            fileInfo.relativeUrl = [NSString stringWithFormat:@"%@/%@.ts",[BNTool uuidWithUrl:OriUrlString],@(fileInfo.index)];
            fileInfo.diskPath =  [NSString stringWithFormat:@"%@/%@",rootPath,fileInfo.relativeUrl];
            [fileInfos addObject:fileInfo];
            tsRange = [m3u8String rangeOfString:@"#EXTINF:"];
            if (tsRange.location != NSNotFound) {
                m3u8String = [m3u8String subStringForm:@"#EXTINF:" offset:0];
            }
        }
    }
    NSLog(@"analysis compelte");
    info.fileInfos = fileInfos;
    NSParameterAssert(resultBlock);
    resultBlock(nil,info);
}

+ (NSString*)synthesisLocalM3u8Withm3u8Info:(BNM3U8PlistInfo *)m3u8Info withLocaHost:(nonnull NSString *)localhost
{
    if (!localhost.length) {
        localhost = @"http://127.0.0.1:8080";
    }
    NSString *newM3u8String = @"";
    
    NSString *header = @"#EXTM3U\n";
    if (m3u8Info.version.length) {
        header = [header stringByAppendingString:[NSString stringWithFormat:@"#EXT-X-VERSION:%ld\n",(long)m3u8Info.version.integerValue]];
    }
    if (m3u8Info.targetduration.length) {
        header = [header stringByAppendingString:[NSString stringWithFormat:@"#EXT-X-TARGETDURATION:%ld\n",(long)m3u8Info.targetduration.integerValue]];
    }
    if (m3u8Info.mediaSequence.length) {
        header = [header stringByAppendingString:[NSString stringWithFormat:@"#EXT-X-MEDIA-SEQUENCE:%ld\n",(long)m3u8Info.mediaSequence.integerValue]];
    }
    
    __block NSString *keyStr = @"";
    __block NSString *body = @"";
    
    [m3u8Info.fileInfos enumerateObjectsUsingBlock:^(BNM3U8fileInfo * _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
        if(idx == -1 ){
            keyStr = [NSString stringWithFormat:@"#EXT-X-KEY:METHOD=%@,URI=\"%@\",IV=%@\n",m3u8Info.keyMethod,obj.relativeUrl,m3u8Info.keyIv];
        }
        else{
            NSString *tsInfo = [NSString stringWithFormat:@"#EXTINF:%.6lf,\n%@\n",obj.duration.floatValue,[localhost stringByAppendingString:obj.relativeUrl]];
            body =  [body stringByAppendingString:tsInfo];
            if (obj.isHasDiscontiunity) body = [body stringByAppendingString:@"#EXT-X-DISCONTINUITY\n"];
        }
    }];
    
    newM3u8String = [[[[newM3u8String stringByAppendingString:header] stringByAppendingString:keyStr] stringByAppendingString:body] stringByAppendingString:@"#EXT-X-ENDLIST"];
    
    return newM3u8String;
}

@end
