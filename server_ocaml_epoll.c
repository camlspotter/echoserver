#include <caml/mlvalues.h>
#include <caml/alloc.h>
#include <caml/memory.h>
#include <caml/fail.h>

#include <sys/epoll.h>

 // Defined in OCaml's otherlibs/unix/unixsupport.{c,h}
#define Nothing ((value) 0)
extern void uerror(char *cmdname, value cmdarg);

// typical bit flags

#define NUM_EPOLL_EVENTS 13
int caml_epoll_events[NUM_EPOLL_EVENTS] = {
    EPOLLIN,
    EPOLLPRI,
    EPOLLOUT,
    EPOLLRDNORM,
    EPOLLRDBAND,
    EPOLLWRNORM,
    EPOLLWRBAND,
    EPOLLMSG,
    EPOLLERR,
    EPOLLHUP,
    EPOLLRDHUP,
    EPOLLONESHOT,
    EPOLLET 
};

inline value caml_to_c_epoll_event_flags(value caml)
{
    int res = 0;
    int size = Wosize_val(caml);
    int register i;
    for(i = 0; i < size; i++){
        res |= caml_epoll_events[Int_val(Field(caml, i))];
    }
    return caml_copy_int32(res);
}

CAMLprim value c_to_caml_epoll_event_flags(value flags)
{
    CAMLparam0();
    CAMLlocal2(res, tmp);
    res = Val_int(0);
    int register i;
    int iflags = Int32_val(flags);
    for(i = 0; i < NUM_EPOLL_EVENTS; i++){
        if( iflags & caml_epoll_events[i] ){
            tmp = caml_alloc_small(2, 0);
            Field(tmp, 0) = Val_int(i);
            Field(tmp, 1) = res;
            res = tmp;
        }
    }
    CAMLreturn(res);
}

CAMLprim value caml_epoll_create(value size)
{
    int ret = epoll_create(Int_val(size));
    if (ret == -1) uerror("epoll_create", Nothing);
    return Val_int(ret); 
}

CAMLprim void caml_epoll_ctl_add(value epfd, value fd, value flags)
{
    struct epoll_event ev;
    ev.events = Int32_val(flags);
    ev.data.fd = Int_val(fd);

    int ret = epoll_ctl(Int_val(epfd), EPOLL_CTL_ADD, Int_val(fd), &ev);
    if (ret == -1) uerror("epoll_ctl_add", Nothing);
    return;
}

CAMLprim void caml_epoll_ctl_mod(value epfd, value fd, value flags)
{
    struct epoll_event ev;
    ev.events = Int32_val(flags);
    ev.data.fd = Int_val(fd);

    int ret = epoll_ctl(Int_val(epfd), EPOLL_CTL_MOD, Int_val(fd), &ev);
    if (ret == -1) uerror("epoll_ctl_mod", Nothing);
    return;
}

CAMLprim void caml_epoll_ctl_del(value epfd, value fd)
{
    int ret = epoll_ctl(Int_val(epfd), EPOLL_CTL_DEL, Int_val(fd), NULL);
    if (ret == -1) uerror("epoll_ctl_del", Nothing);
    return;
}

CAMLprim value caml_epoll_wait(value epfd, 
                               value maxevents, 
                               value timeout)
{
    CAMLparam3(epfd, maxevents, timeout);
    CAMLlocal3(res, tmp, vevents);
    int imaxevents = Int_val(maxevents);
    struct epoll_event events[imaxevents]; // no check of maxevents > 0
    int nfd = epoll_wait(Int_val(epfd), events, imaxevents, Int_val(timeout));
    if( nfd == -1 ) uerror("epoll_wait", Nothing);
    res = caml_alloc_tuple(nfd);
    int i;
    for (i = 0; i < nfd; i++){
        vevents = caml_copy_int32(events[i].events); // it must be before alloc_small! Since alloc_small hates other allocs!
        tmp = caml_alloc_small(2, 0);
        Field(tmp, 0) = Val_int(events[i].data.fd);
        Field(tmp, 1) = vevents;
        Store_field(res, i, tmp);
    }
    CAMLreturn(res);
}




