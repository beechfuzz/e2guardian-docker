#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <errno.h>
#include <string.h>
#include <fcntl.h>
#include <signal.h>
#include <sys/types.h>
#include <sys/socket.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#define VERSION 23
#define BUFSIZE 8096
#define ERROR      42
#define LOG        44
#define FORBIDDEN 403
#define NOTFOUND  404

#ifndef SIGCLD
#   define SIGCLD SIGCHLD
#endif

char *g_logfile;

struct {
    char *ext;
    char *filetype;
} 

extensions [] = {
    {"crt", "application/x-x509-ca-cert" },
    {"der", "application/x-x509-ca-cert" },
    {"html","text/html" },
    {0,0} 
};

void usage(){

    int i;
	
	(void)printf("Usage: nweb PORT TOP_DIRECTORY\t\tversion %d\n\n"
        "\tnweb is a small and very safe mini web server\n"
        "\tnweb only servers out file/web pages with extensions named below\n"
        "\t and only from the named directory or its sub-directories.\n"
        "\tThere is no fancy features = safe and secure.\n\n"
        "\tExample: nweb 8181 /home/nwebdir &\n\n"
        "\tOnly Supports:", VERSION);
    for( i=0; extensions[i].ext != 0; i++ ){
        (void)printf(" %s",extensions[i].ext);
	}
    (void)printf("\n\tNot Supported: URLs including \"..\", Java, Javascript, CGI\n"
        "\tNot Supported: directories / /etc /bin /lib /tmp /usr /dev /sbin \n"
        "\tNo warranty given or implied\n\tNigel Griffiths nag@uk.ibm.com\n"  );
    exit(0);

}

void logger(int type, char *s1, char *s2, int socket_fd){
    int fd ;
    char logbuffer[BUFSIZE*2];

	switch (type) {
        case ERROR: 
			(void)sprintf(logbuffer,"ERROR: %s:%s Errno=%d exiting pid=%d",s1, s2, errno,getpid());
            break;
        case FORBIDDEN:
            (void)write(socket_fd, "HTTP/1.1 403 Forbidden\nContent-Length: 185\nConnection: close\nContent-Type: text/html\n\n<html><head>\n<title>403 Forbidden</title>\n</head><body>\n<h1>Forbidden</h1>\nThe requested URL, file type or operation is not allowed on this simple static file webserver.\n</body></html>\n",271);
			(void)sprintf(logbuffer,"FORBIDDEN: %s:%s",s1, s2);
            break;
        case NOTFOUND:
            (void)write(socket_fd, "HTTP/1.1 404 Not Found\nContent-Length: 136\nConnection: close\nContent-Type: text/html\n\n<html><head>\n<title>404 Not Found</title>\n</head><body>\n<h1>Not Found</h1>\nThe requested URL was not found on this server.\n</body></html>\n",224);
            (void)sprintf(logbuffer,"NOT FOUND: %s:%s",s1, s2);
            break;
        case LOG: 
			(void)sprintf(logbuffer," INFO: %s:%s:%d",s1, s2,socket_fd); 
			break;
    }
    
	// Write to log.  No checks here, nothing can be done with a failure anyway
	if((fd = open(g_logfile, O_CREAT| O_WRONLY | O_APPEND,0644)) >= 0) {
        (void)write(fd,logbuffer,strlen(logbuffer));
        (void)write(fd,"\n",1);
        (void)close(fd);
    }
    
    // No checks here, nothing can be done with a failure anyway
	if(type == ERROR || type == NOTFOUND || type == FORBIDDEN){
		exit(3);
	}

}

// this is a child web server process, so we can exit on errors
void web(int fd, int hit){

    int j, file_fd, buflen;
    long i, ret, len;
    char * fstr;
    static char buffer[BUFSIZE+1]; /* static so zero filled */

	// read Web request in one go
    ret =read(fd,buffer,BUFSIZE);
    
	// read failure stop now
	if(ret == 0 || ret == -1) {
        logger(FORBIDDEN,"failed to read browser request","",fd);
    }
	
	// return code is valid chars
    if(ret > 0 && ret < BUFSIZE){
        // terminate the buffer
		buffer[ret]=0;
	} else { 
		buffer[0]=0;
	}
    
	// remove CF and LF characters
	for(i=0;i<ret;i++){
        if(buffer[i] == '\r' || buffer[i] == '\n'){
            buffer[i]='*';
		}
	}
    
	// Log request
	logger(LOG,"request",buffer,hit);
    
	if( strncmp(buffer,"GET ",4) && strncmp(buffer,"get ",4) ) {
            logger(FORBIDDEN,"Only simple GET operation supported",buffer,fd);
    }
    
	//  null terminate after the second space to ignore extra stuff
	for(i=4;i<BUFSIZE;i++) {
        // string is "GET URL " +lots of other stuff
		if(buffer[i] == ' ') {
            buffer[i] = 0;
            break;
        }
    }
    
	// check for illegal parent directory use ..
	for(j=0;j<i-1;j++){
        if(buffer[j] == '.' && buffer[j+1] == '.') {
            logger(FORBIDDEN,"Parent directory (..) path names not supported",buffer,fd);
        }
	}

	// convert no filename to index file
    if( !strncmp(&buffer[0],"GET /\0",6) || !strncmp(&buffer[0],"get /\0",6) ){
        (void)strcpy(buffer,"GET /index.html");
	}

    // work out the file type and check we support it
    buflen=strlen(buffer);
    fstr = (char *)0;
    for(i=0;extensions[i].ext != 0;i++) {
        len = strlen(extensions[i].ext);
        if( !strncmp(&buffer[buflen-len], extensions[i].ext, len)) {
            fstr =extensions[i].filetype;
            break;
        }
    }

    // Log unsupported file type
	if(fstr == 0) {
		logger(FORBIDDEN,"file extension type not supported",buffer,fd);
	}

	// open the file for reading
    if(( file_fd = open(&buffer[5],O_RDONLY)) == -1) {
        logger(NOTFOUND, "failed to open file",&buffer[5],fd);
    }

    logger(LOG,"SEND",&buffer[5],hit);
    
	// lseek to the file end to find the length
	len = (long)lseek(file_fd, (off_t)0, SEEK_END);
	// lseek back to the file start ready for reading
	(void)lseek(file_fd, (off_t)0, SEEK_SET);

	// Header + a blank line
    (void)sprintf(buffer,"HTTP/1.1 200 OK\nServer: nweb/%d.0\nContent-Length: %ld\nConnection: close\nContent-Type: %s\n\n", VERSION, len, fstr);
    logger(LOG,"Header",buffer,hit);
    (void)write(fd,buffer,strlen(buffer));

    // send file in 8KB block - last block may be smaller
    while (  (ret = read(file_fd, buffer, BUFSIZE)) > 0 ) {
        (void)write(fd,buffer,ret);
    }
    
	// allow socket to drain before signalling the socket is closed
	sleep(1);
    close(fd);
    
	exit(1);
}

int main(int argc, char **argv){

    int i, numargs, port, pid, listenfd, socketfd, hit;
    socklen_t length;
	static struct sockaddr_in cli_addr; /* static = initialised to zeros */
    static struct sockaddr_in serv_addr; /* static = initialised to zeros */
	char *logfile, *topdir, *msg;
	
	// Validate correct number of arguments
    numargs = argc-1;
	if (numargs < 2 || numargs > 3 || !strcmp(argv[1], "-?")){
		usage();
    }

	// Assign and validate port variable
	port = atoi(argv[1]);
    if ( port < 0 || port >60000 ){
		printf("\nERROR: %s","Invalid port number (try 1->60000)\n");
		exit(3);
    }

	// Assign and validate top directory variable
	topdir = argv[2];
    if(chdir(topdir) == -1){
        (void)printf("ERROR: Can't Change to directory %s\n",topdir);
        exit(4);
    }

	// Assign log file global variable
	if (argc > 3){
        logfile = argv[3];
    } else {
        logfile = "nweb.log";
    }
    g_logfile = (char *) malloc(strlen(logfile) + 1);
    strcpy(g_logfile,logfile);
    
	// Become deamon + unstopable and no zombies children (= no wait())
    if(fork() != 0){
        // parent returns OK to shell
		return 0;
	}

	// ignore child death and terminal hangups
    (void)signal(SIGCLD, SIG_IGN);
    (void)signal(SIGHUP, SIG_IGN);
    
	// Close open files
	for(i=0;i<32;i++){
        (void)close(i);
	}

	// Break away from process group
    (void)setpgrp();

    logger(LOG,"nweb starting",(char*) &port,getpid());
    
	// Setup the network socket
    if ((listenfd = socket(AF_INET, SOCK_STREAM,0)) <0){
        logger(ERROR, "system call","socket",0);
	}
    serv_addr.sin_family = AF_INET;
    serv_addr.sin_addr.s_addr = htonl(INADDR_ANY);
    serv_addr.sin_port = htons(port);
    if(bind(listenfd, (struct sockaddr *)&serv_addr,sizeof(serv_addr)) <0){
        logger(ERROR,"system call","bind",0);
	}
    if( listen(listenfd,64) <0){
        logger(ERROR,"system call","listen",0);
	}
    for(hit=1; ;hit++) {
        length = sizeof(cli_addr);
        if((socketfd = accept(listenfd, (struct sockaddr *)&cli_addr, &length)) < 0){
            logger(ERROR,"system call","accept",0);
		}
        if((pid = fork()) < 0) {
            logger(ERROR,"system call","fork",0);
        } else {
            // child
			if(pid == 0) {
                (void)close(listenfd);
                // never returns
				web(socketfd,hit);
            // parent
			} else {
                (void)close(socketfd);
            }
        }
    }

	// Free up our resources
	free((void *) g_logfile);

}
